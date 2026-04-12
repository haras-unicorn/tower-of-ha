{ self, ... }:

{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-traefik-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-traefik-disabled";
        toh.test.disabledService.module = {
          imports = [
            self.nixosModules.services-traefik
            self.nixosModules.services-consul
          ];
        };
        toh.test.disabledService.enable = true;
        toh.test.disabledService.name = "traefik.service";

      };

      checks.test-services-traefik-cluster =
        let
          backendPort = 8080;
          backendPortString = builtins.toString backendPort;

          amount = 3;
          amountString = builtins.toString amount;
        in
        pkgs.tohPackages.testers.runToHTest {
          name = "services-traefik-cluster";
          toh.test.clusters.node.amount = amount;
          toh.test.clusters.node.module =
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              backendScript = pkgs.writeText "test-backend-script" ''
                import http.server
                import socketserver
                import sys

                PORT = ${backendPortString}
                NODE_NAME = '${config.toh.host.name}'

                class Handler(http.server.BaseHTTPRequestHandler):
                    def do_GET(self):
                        if self.path == '/health':
                            self.send_response(200)
                            self.send_header('Content-type', 'text/plain')
                            self.end_headers()
                            self.wfile.write(b'OK')
                        else:
                            self.send_response(200)
                            self.send_header('Content-type', 'text/plain')
                            self.end_headers()
                            self.wfile.write(f'Response from {NODE_NAME}'.encode())
                    def log_message(self, format, *args):
                        pass  # Suppress logs

                with socketserver.TCPServer(('${config.toh.host.ip}', PORT), Handler) as httpd:
                    httpd.serve_forever()
              '';

              backendApp = pkgs.writeShellApplication {
                name = "test-backend";
                runtimeInputs = [ pkgs.python3 ];
                text = ''python3 "${backendScript}"'';
              };
            in
            {
              imports = [
                self.nixosModules.services-traefik
                self.nixosModules.services-consul
              ];

              toh.test.openssl.enable = true;
              toh.traefik.enable = true;
              toh.consul.enable = true;

              toh.services = [
                {
                  port = backendPort;
                  name = "test-backend";
                  health = "http:///health";
                }
              ];

              systemd.services.test-backend = {
                description = "Test backend service for traefik load balancing";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "simple";
                  ExecStart = lib.getExe backendApp;
                  Restart = "always";
                };
              };
            };
          toh.test.commands.enable = true;
          toh.test.commands.perNode = [
            ''command_node.wait_for_unit("network-online.target")''
            ''command_node.wait_for_unit("test-backend.service")''
            ''command_node.wait_for_unit("consul.service")''
            ''command_node.wait_for_unit("traefik.service")''
            ''command_node.succeed("iptables -L -n | grep -q '443'")''
            (node: ''
              command_node.wait_until_succeeds("""
                test -n "$(curl -sk https://${node.toh.host.ip}:8500/v1/status/leader)"
              """)
            '')
            (
              { node, nodea, ... }:
              builtins.map (other: ''
                command_node.wait_until_succeeds("""
                  curl -sk https://${node.toh.host.ip}:8500/v1/agent/members | \
                    grep -q '${other.toh.host.name}'
                """)
              '') nodea
            )
            (node: ''
              command_node.wait_until_succeeds("""
                curl -sk https://${node.toh.host.ip}:8500/v1/catalog/service/traefik | \
                  grep -q 'traefik'
              """)
            '')
            (node: ''
              command_node.wait_until_succeeds("""
                count=$(curl -sk https://${node.toh.host.ip}:8500/v1/catalog/service/traefik | \
                  jq length)
                [ "$count" -eq "${amountString}" ]
              """)
            '')
            (node: ''
              command_node.wait_until_succeeds("""
                count=$(curl -sk https://${node.toh.host.ip}:8500/v1/catalog/service/test-backend | \
                  jq length)
                [ "$count" -eq "${amountString}" ]
              """)
            '')
            ''command_node.succeed("pgrep -x traefik")''
            (node: ''
              command_node.succeed("""
                curl -s http://${node.toh.host.ip}:${backendPortString}/ | \
                  grep -q 'Response from ${node.toh.host.name}'
              """)
            '')
          ];
        };
    };
}
