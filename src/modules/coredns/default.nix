# TODO: dnssec and dnsovertls

{
  toh.lib.nixosModules.services-coredns =
    {
      lib,
      config,
      pkgs,
      tohLib,
      ...
    }:

    let
      cfg = config.toh.services.coredns;
      machines = config.toh.cluster.machinea;
      nodeDomain = config.toh.meta.domains.node;
      serviceDomain = config.toh.meta.domains.service;

      otherCorednsMachines = tohLib.otherServiceMachines "coredns";

      relays = config.toh.meta.relays;
    in
    {
      options.toh.services = {
        coredns = {
          enable = lib.mkEnableOption "CoreDNS";

          forwarders = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              # NOTE: Cloudflare
              "1.1.1.1"
              "1.0.0.1"
              # NOTE: Google
              "8.8.8.8"
              "8.8.4.4"
            ];
            description = "Upstream DNS forwarders for external queries";
          };
        };
      };
      config = lib.mkMerge [
        (lib.mkIf (tohLib.anyServiceMachines "coredns") {
          networking.networkmanager.dns = "none";
          networking.nameservers = builtins.map (machine: machine.meta.network.ip) otherCorednsMachines;
        })
        (lib.mkIf cfg.enable {
          networking.networkmanager.dns = "none";
          networking.nameservers = lib.mkBefore [ "127.0.0.1" ];

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
                  ${tohLib.strings.indentTail "    " (
                    builtins.concatStringsSep "\n" (
                      builtins.map (relay: ''answer "{{ .Name }} 60 IN A ${relay}"'') relays
                    )
                  )}
                }
              }

              . {
                forward . ${builtins.concatStringsSep " " cfg.forwarders}
              }
            '';
          };
        })
      ];
    };
}
