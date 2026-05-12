# TODO: dnssec and dnsovertls

{
  toh.lib.nixosModules.services-coredns =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    let
      cfg = config.toh.services.coredns;
      machines = config.toh.cluster.machinea;
      nodeDomain = config.toh.meta.domains.node;
      serviceDomain = config.toh.meta.domains.service;
    in
    {
      options.toh.services = {
        coredns = {
          enable = lib.mkEnableOption "CoreDNS";

          forwarders = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "1.1.1.1"
              "1.0.0.1"
              "8.8.8.8"
              "8.8.4.4"
            ];
            description = "Upstream DNS forwarders for external queries";
          };
        };
      };
      config = lib.mkIf cfg.enable {
        networking.networkmanager.dns = "none";
        networking.nameservers = [ "127.0.0.1" ];

        services.coredns = {
          enable = true;
          config = ''
            ${nodeDomain} {
              hosts {
                ${builtins.concatStringsSep "\n" (
                  map (m: "${m.config.toh.meta.network.ip} ${m.name}.${nodeDomain}") machines
                )}
                fallthrough
              }
            }

            ${serviceDomain} {
              template IN A {
                answer "{{ .Name }} 60 IN A 127.0.0.1"
              }
            }

            . {
              # NOTE: Cloudflare and Google
              forward . ${builtins.concatStringsSep " " cfg.forwarders}
            }
          '';
        };
      };
    };
}
