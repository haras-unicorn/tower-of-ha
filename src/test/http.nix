{ lib, tohLib, ... }:

let
  httpSubmodule = {
    options = {
      enable = lib.mkEnableOption "HTTP test server";

      ssl = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable HTTPS for the HTTP server";
      };

      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 80;
        description = "HTTP port for this server";
      };

      httpsPort = lib.mkOption {
        type = lib.types.port;
        default = 443;
        description = "HTTPS port for this server (only works with ssl = true)";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall for the HTTP server";
      };

      domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of domains for the HTTP server";
      };

      handler = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Python snippet to execute inside the handler function:

          def _do(self, method: str):
            now = datetime.now().isoformat()
            id = str(uuid.uuid4())

            parsed = urllib.parse.urlparse(self.path)
            path = parsed._asdict()
            params = urllib.parse.parse_qs(parsed.query)
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode()
            headers = dict(self.headers)

            status_code = 200
            response = 'OK'
            content_type = 'text/plain'

            ''${indentedHandler}

            self.send_response(status_code)
            self.send_header('Content-Type', content_type)
            self.end_headers()
            self.wfile.write(response.encode())
        '';
      };
    };
  };
in
{
  toh.lib.test.testModules.http =
    {
      lib,
      config,
      ...
    }:
    {
      options.toh.test = {
        http = lib.mkOption {
          description = "HTTP test servers";
          default = { };
          type = lib.types.attrsOf (lib.types.submodule httpSubmodule);
        };
      };

      config = {
        toh.test.dns.zones = lib.mkMerge (
          builtins.map (
            { name, value }:
            lib.mkIf value.enable (
              tohLib.dns.routeToIp value.domains config.nodes."http-${name}".toh.meta.network.ip
            )
          ) (lib.attrsToList config.toh.test.http)
        );

        toh.test.commands.prefix = lib.mkMerge (
          builtins.map (
            { name, value }:
            let
              pythonName = builtins.replaceStrings [ "-" ] [ "_" ] name;
            in
            lib.mkIf value.enable (
              lib.mkBefore ''
                http_${pythonName}.wait_for_unit("http.service")
              ''
            )
          ) (lib.attrsToList config.toh.test.http)
        );

        nodes = lib.mkMerge (
          builtins.map (
            { name, value }:
            lib.mkIf value.enable {
              "http-${name}".toh.test.http = value;
            }
          ) (lib.attrsToList config.toh.test.http)
        );
      };
    };

  toh.lib.test.nixosModules.http =
    {
      lib,
      config,
      pkgs,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.test.http;

      httpPort = cfg.httpPort;
      httpsPort = cfg.httpsPort;

      stateDir = "http";

      script = pkgs.writeText "http.py" ''
        HTTP_PORT = ${builtins.toString httpPort}

        ${lib.optionalString cfg.ssl ''
          HTTPS_PORT = ${builtins.toString httpsPort}
          SSL_CERT = "${config.toh.meta.sops.secrets."http-public".path}"
          SSL_KEY = "${config.toh.meta.sops.secrets."http-private".path}"
        ''}

        LOG_FILE = "/var/lib/${stateDir}/log.jsonl"
        STORE_FILE = "/var/lib/${stateDir}/store.json"

        import http.server
        import socketserver
        import json
        import urllib.parse
        from datetime import datetime
        import os
        import threading
        from socketserver import ThreadingTCPServer
        import ssl
        import time
        import sys
        import signal
        import traceback
        import uuid

        ThreadingTCPServer.allow_reuse_address = True

        store = {}

        def signal_handler(signum, frame):
          print("Shutting down gracefully...")

          http_server.shutdown()

          ${lib.optionalString cfg.ssl ''
            https_server.shutdown()
          ''}

          sys.exit(0)

        class HTTPHandler(http.server.BaseHTTPRequestHandler):
          def log_message(self, format, *args):
            if " 2" not in format % args:
              print(f"[HTTP] {self.address_string()} - {format % args}")

          def _do(self, method: str):
            now = datetime.now().isoformat()
            id = str(uuid.uuid4())

            parsed = urllib.parse.urlparse(self.path)
            path = parsed._asdict()
            params = urllib.parse.parse_qs(parsed.query)
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode()
            headers = dict(self.headers)

            status_code = 200
            response = 'OK'
            content_type = 'text/plain'

            try:
              ${tohLib.strings.indentTail "      " cfg.handler}
            except Exception as e:
              print(f"[HTTP] ERROR: Handler raised exception {e}")
              traceback.print_exc()

            self.send_response(status_code)
            self.send_header('Content-Type', content_type)
            self.end_headers()
            self.wfile.write(response.encode())

            with open(LOG_FILE, 'a') as f:
              data = {
                'id': id,
                'timestamp': now,
                'store': store,
                'request': {
                  'method': method,
                  'path': path,
                  'params': params,
                  'body': body,
                  'headers': headers
                },
                'response': {
                  'status_code': status_code,
                  'response': response,
                  'content_type': content_type
                }
              }
              f.write(f"{json.dumps(data)}\n")

            with open(STORE_FILE, 'w') as f:
              data = {
                'last_request': {
                  'id': id,
                  'timestamp': now
                },
                'records': store,
              }
              f.write(f"{json.dumps(data)}\n")

          def do_GET(self):
            self._do('GET')

          def do_POST(self):
            self._do('POST')

          def do_PUT(self):
            self._do('PUT')

          # Perform proper TLS close if the connection is SSL-wrapped
          def finish(self):
              if hasattr(self.request, 'unwrap'):
                  try:
                      self.request.unwrap()
                  except Exception:
                      pass
              super().finish()

        try:
          signal.signal(signal.SIGTERM, signal_handler)
          signal.signal(signal.SIGINT, signal_handler)

          os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

          print(f"[HTTP] Starting test HTTP server...")
          print(f"[HTTP] Log file: {LOG_FILE}")
          print(f"[HTTP] HTTP port: {HTTP_PORT}")

          http_server = ThreadingTCPServer(("0.0.0.0", HTTP_PORT), HTTPHandler)

          http_thread = threading.Thread(target=http_server.serve_forever, daemon=True)
          http_thread.start()

          ${lib.optionalString cfg.ssl (
            tohLib.strings.indentTail "  " ''
              print(f"[HTTP] SSL cert: {SSL_CERT}")
              print(f"[HTTP] SSL key: {SSL_KEY}")
              print(f"[HTTP] HTTPS port: {HTTPS_PORT}")

              https_server = ThreadingTCPServer(("0.0.0.0", HTTPS_PORT), HTTPHandler)

              context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
              context.load_cert_chain(certfile=SSL_CERT, keyfile=SSL_KEY)
              https_server.socket = context.wrap_socket(https_server.socket, server_side=True)

              https_thread = threading.Thread(target=https_server.serve_forever, daemon=True)
              https_thread.start()
            ''
          )}

          print("[HTTP] Server started successfully")

          try:
            while True:
              time.sleep(3600)
          except KeyboardInterrupt:
            signal_handler(signal.SIGINT, None)
        except Exception as e:
          print(f"[HTTP] ERROR: {e}")
          traceback.print_exc()
          sys.exit(1)
      '';
    in
    {
      options.toh.test = {
        http = lib.mkOption {
          type = lib.types.submodule httpSubmodule;
          default = { };
          description = "Test HTTP server";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.http = {
          description = "Test HTTP server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            AmbientCapabilities = "CAP_NET_BIND_SERVICE";
            Type = "simple";
            Restart = "always";
            User = "http";
            Group = "http";
            StateDirectory = stateDir;
            ExecStart = "${lib.getExe pkgs.python3} ${script}";
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (
          [
            httpPort
          ]
          ++ lib.optional cfg.ssl httpsPort
        );

        users.users.http = {
          isSystemUser = true;
          group = "http";
          description = "Test HTTP server system user";
        };

        users.groups.http = { };

        toh.meta.sops.secrets."http-public" = lib.mkIf cfg.ssl {
          owner = "http";
          group = "http";
          mode = "0400";
        };

        toh.meta.sops.secrets."http-private" = lib.mkIf cfg.ssl {
          owner = "http";
          group = "http";
          mode = "0400";
        };

        toh.meta.cryl.machine = lib.mkIf cfg.ssl [
          {
            http = {
              generations = [
                {
                  generator = "tls-leaf";
                  arguments = {
                    common_name = "toh";
                    organization = "ToH";
                    sans = [
                      "localhost"
                      "${config.toh.meta.network.ip}"
                      "127.0.0.1"
                    ]
                    ++ cfg.domains;
                    config = "http-cert-config";
                    request_config = "http-cert-request-config";
                    private = "http-private";
                    request = "http-cert-request";
                    ca_private = "cluster/openssl-ca-private";
                    ca_public = "cluster/openssl-ca-public";
                    serial = "cluster/openssl-ca-serial";
                    public = "http-public";
                    renew = true;
                  };
                }
              ];
            };
          }
        ];

        toh.pki.generateCa = lib.mkIf cfg.ssl true;
      };
    };
}
