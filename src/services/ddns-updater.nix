{ self, ... }:

{
  flake.nixosModules.services-ddns-updater =
    { lib, config, ... }:
    let
      cfg = config.toh.ddns-updater;

      httpPort = 8000;
      healthPort = 9999;
    in
    {
      options.toh = {
        ddns-updater = {
          enable = lib.mkEnableOption "ddns-updater";

          period = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "Refresh period";
          };

          logLevel = lib.mkOption {
            type = lib.types.enum [
              "debug"
              "info"
              "warning"
              "error"
            ];
            default = "info";
            description = "Log level";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.ddns-updater.enable = true;
        services.ddns-updater.environment = {
          CONFIG_FILEPATH = config.sops.secrets."ddns-updater-settings".path;
          LISTENING_ADDRESS = ":${builtins.toString httpPort}";
          HEALTH_SERVER_ADDRESS = ":${builtins.toString healthPort}";
          # NOTE: keeping this here for easier debug later
          # GODEBUG = "netdns=go+2";
          RESOLVER_ADDRESS = "${builtins.head config.networking.nameservers}:53";
          PERIOD = cfg.period;
          LOG_LEVEL = cfg.logLevel;
        };
        users.users.ddns-updater = {
          group = "ddns-updater";
          description = "DDNS updater service user";
          isSystemUser = true;
        };
        users.groups.ddns-updater = { };
        systemd.services.ddns-updater = {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "ddns-updater";
            Group = lib.mkForce "ddns-updater";
            Restart = lib.mkForce "always";
          };
        };

        networking.firewall.allowedTCPPorts = [
          httpPort
          healthPort
        ];

        toh.services = [
          {
            name = "ddns-updater";
            port = httpPort;
            health = "http://";
          }
        ];

        sops.secrets."ddns-updater-settings" = {
          owner = "ddns-updater";
          group = "ddns-updater";
          mode = "0400";
        };

        toh.cryl.host.ddns-updater = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/ddns-updater-duckdns";
                to = "ddns-updater-duckdns";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/ddns-updater-cloudflare";
                to = "ddns-updater-cloudflare";
              };
            }
          ];
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "ddns-updater-settings";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DUCKDNS = "ddns-updater-duckdns";
                    CLOUDFLARE = "ddns-updater-cloudflare";
                  };
                };
                template = ''
                  {
                    "settings": [
                      {{{DUCKDNS}}},
                      {{{CLOUDFLARE}}}
                    ]
                  }
                '';
              };
            }
          ];
        };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-ddns-updater-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-ddns-updater-disabled";
        toh.test.disabledService.enable = true;
        toh.test.disabledService.module = {
          imports = [
            self.nixosModules.services-ddns-updater
          ];
        };
        toh.test.disabledService.name = "ddns-updater";

      };

      checks.test-services-ddns-updater-enabled = pkgs.tohPackages.testers.runToHTest (
        { nodes, ... }:
        {
          name = "services-ddns-updater-enabled";

          toh.test.dns.enable = true;

          toh.test.http.ddns = {
            domains = [
              "duckdns.org"
              "www.duckdns.org"
              "api.cloudflare.com"
              "api.dynu.com"
              "api.dynv6.com"
              "api.dreamhost.com"
              "api.namecheap.com"
              "api.godaddy.com"
              "api.hetzner.cloud"
              "api.cloudns.net"
              "api.infomaniak.com"
              "api.porkbun.com"
              "api.gandi.net"
              "api.vultr.com"
              "api.linode.com"
              "api.desec.io"
              "api.domeneshop.no"
              "api.easydns.com"
              "api.freedns.afraid.org"
              "api.he.net"
              "api.inwx.com"
              "api.ionos.com"
              "api.loopia.com"
              "api.luadns.com"
              "api.myaddr.tools"
              "api.name.com"
              "api.netcup.de"
              "api.noip.com"
              "api.njalla.com"
              "api.ovh.com"
              "api.route53.amazonaws.com"
              "api.spdyn.de"
              "api.selfhost.de"
              "api.servercow.de"
              "api.strato.de"
              "api.variomedia.de"
              "api.zoneedit.com"
              "dyn.dns.he.net"
              "dyndns.strato.com"
              "nic.changeip.com"
              "dynupdate.no-ip.com"
              "dynupdate.ovh.com"
            ];
            handler = ''
              host = headers.get('Host', ''').lower()

              if 'cloudflare' in host:
                if body is not None and body != "":
                  id = str(uuid.uuid4())
                  json_body = json.loads(body)
                  name = json_body.get('name', 'localhost')
                  ip = json_body.get('content', '127.0.0.1')
                  store[name] = {
                    'id': id,
                    'ip': ip
                  }
                  response = {
                    "success": True,
                    "errors": [],
                    "result": {
                      "id": id,
                      "content": ip,
                    }
                  }
                else:
                  name = params.get('domains', ['localhost'])[0]
                  stored = store.get(name)
                  if stored is not None:
                    response = {
                      "success": True,
                      "errors": [],
                      "result": [{
                        "id": stored['id'],
                        "content": stored['ip']
                      }]
                    }
                  else:
                    response = {
                      "success": True,
                      "errors": [],
                      "result": []
                    }
                response = json.dumps(response)
                content_type = 'application/json'

              elif 'duckdns' in host:
                id = str(uuid.uuid4())
                name = params.get('domains', ['localhost'])[0]
                ip = params.get('ip', ['localhost'])[0]
                store[name] = {
                  'id': id,
                  'ip': ip
                }
                response = f'OK\n{ip}'
            '';
          };

          toh.test.http.ip = {
            domains = [
              "api.ipify.org"
              "api6.ipify.org"
              "api64.ipify.org"
              "icanhazip.com"
              "ipv4.icanhazip.com"
              "ipv6.icanhazip.com"
              "ifconfig.io"
              "ident.me"
              "v4.ident.me"
              "v6.ident.me"
              "ipinfo.io"
              "checkip.spdyn.de"
              "ipleak.net"
              "ip.nnev.de"
              "ip4.nnev.de"
              "ip6.nnev.de"
              "wtfismyip.com"
              "ipv4.wtfismyip.com"
              "ipv6.wtfismyip.com"
              "api.seeip.org"
              "ipv4.seeip.org"
              "ipv6.seeip.org"
              "ip.changeip.com"
            ];

            handler = ''
              host = headers.get('Host', ''').lower()

              def get_client_ip():
                client_addr = self.client_address[0]
                if client_addr.startswith('::ffff:'):
                  return client_addr[7:]
                return client_addr

              def get_ipv4():
                ip = get_client_ip()
                if '.' in ip and ':' not in ip:
                  return ip
                return None

              def get_ipv6():
                ip = get_client_ip()
                if ':' in ip and not ip.startswith('::ffff:'):
                  return ip
                return None

              ip = "127.0.0.1"

              if 'api.ipify.org' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'api6.ipify.org' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip
              elif 'api64.ipify.org' in host:
                ip = get_client_ip()
                response = ip

              elif host == 'icanhazip.com' or 'ipv4.icanhazip.com' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'ipv6.icanhazip.com' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip

              elif 'ifconfig.io' in host:
                if path == '/ip' or path == '/':
                  ip = get_client_ip()
                  response = ip

              elif 'ident.me' in host:
                if 'v4.ident.me' in host:
                  ip = get_ipv4() or get_client_ip()
                  response = ip
                elif 'v6.ident.me' in host:
                  ip = get_ipv6() or get_client_ip()
                  response = ip
                else:
                  ip = get_client_ip()
                  response = ip

              elif 'ipinfo.io' in host:
                if path == '/ip' or path == '/':
                  ip = get_client_ip()
                  response = ip

              elif 'checkip.spdyn.de' in host:
                ip = get_client_ip()
                response = ip

              elif 'ipleak.net' in host:
                ip = get_client_ip()
                content_type = 'application/json'
                response = json.dumps({
                  "ip": ip,
                  "type": "ipv4" if '.' in ip else "ipv6"
                })

              elif 'ip.nnev.de' in host:
                if 'ip4.nnev.de' in host:
                  ip = get_ipv4() or get_client_ip()
                  response = ip
                elif 'ip6.nnev.de' in host:
                  ip = get_ipv6() or get_client_ip()
                  response = ip
                else:
                  ip = get_client_ip()
                  response = ip

              elif 'wtfismyip.com' in host:
                if 'ipv4.wtfismyip.com' in host:
                  ip = get_ipv4() or get_client_ip()
                  response = ip
                elif 'ipv6.wtfismyip.com' in host:
                  ip = get_ipv6() or get_client_ip()
                  response = ip
                else:
                  ip = get_client_ip()
                  response = ip

              elif 'seeip.org' in host:
                if 'ipv4.seeip.org' in host:
                  ip = get_ipv4() or get_client_ip()
                  response = ip
                elif 'ipv6.seeip.org' in host:
                  ip = get_ipv6() or get_client_ip()
                  response = ip
                else:
                  ip = get_client_ip()
                  response = ip

              elif 'changeip.com' in host:
                ip = get_client_ip()
                response = ip

              else:
                ip = get_client_ip()
                response = ip

              store["ips"] = store.get("ips", []) + [ip]
            '';
          };

          toh.test.cryl.cluster.ddns-updater = {
            generations = [
              {
                generator = "json";
                arguments = {
                  name = "ddns-updater-duckdns";
                  value = {
                    "provider" = "duckdns";
                    # NOTE: has to be on a known zone because otherwise dns just times out
                    "domain" = "test.duckdns.org";
                    "token" = "1ef6dd59-eeb3-48c9-a42a-ef748e5246df";
                    "ip_version" = "ipv4";
                  };
                };
              }
              {
                generator = "json";
                arguments = {
                  name = "ddns-updater-cloudflare";
                  value = {
                    "provider" = "cloudflare";
                    "zone_identifier" = "id";
                    # NOTE: has to be on a known zone because otherwise dns just times out
                    "domain" = "test.cloudflare.com";
                    "ttl" = 600;
                    "token" = "1ef6dd59-eeb3-48c9-a42a-ef748e5246df";
                    "ip_version" = "ipv4";
                    "ipv6_suffix" = "";
                  };
                };
              }
            ];
            exports = [
              {
                exporter = "copy";
                arguments = {
                  from = "ddns-updater-cloudflare";
                  to = "${self.lib.cryl.directories.cluster}/ddns-updater-cloudflare";
                };
              }
              {
                exporter = "copy";
                arguments = {
                  from = "ddns-updater-duckdns";
                  to = "${self.lib.cryl.directories.cluster}/ddns-updater-duckdns";
                };
              }
            ];
          };

          nodes.machine =
            { lib, ... }:
            {
              imports = [
                self.nixosModules.services-ddns-updater
              ];

              toh.ddns-updater.enable = true;
              toh.ddns-updater.period = "10s";
              toh.ddns-updater.logLevel = "debug";

              toh.test.openssl.enable = true;
            };
          toh.test.commands.suffix = ''
            machine.wait_for_unit("ddns-updater.service")

            http_ip.wait_until_succeeds("grep -q '${nodes.machine.toh.host.ip}' /var/lib/http/log.jsonl", timeout=60)
            http_ip.wait_until_succeeds("grep -q '${nodes.machine.toh.host.ip}' /var/lib/http/store.json", timeout=60)

            http_ddns.wait_until_succeeds("grep -q 'test.cloudflare.com' /var/lib/http/log.jsonl", timeout=180)
            http_ddns.wait_until_succeeds("grep -q 'test.duckdns.org' /var/lib/http/log.jsonl", timeout=60)
            http_ddns.wait_until_succeeds("grep -q 'test.cloudflare.com' /var/lib/http/store.json", timeout=60)
            http_ddns.wait_until_succeeds("grep -q 'test.duckdns.org' /var/lib/http/store.json", timeout=60)
            http_ddns.wait_until_succeeds("grep -q '${nodes.machine.toh.host.ip}' /var/lib/http/store.json", timeout=60)
          '';
        }
      );
    };
}
