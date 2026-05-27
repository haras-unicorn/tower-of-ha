# TODO: dnssec and dnsovertls
# TODO: sort service hosts by and set low ttl
# so caching does not disrupt this order a lot
# if something goes down:
# 1. machine
# 2. rack
# 3. datacenter
# 4. region
# 5. other regions

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

      relays =
        if builtins.elem config.toh.meta.network.ip config.toh.meta.relays then
          [ "127.0.0.1" ] ++ config.toh.meta.relays
        else
          config.toh.meta.relays;
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
                bind 127.0.0.1
                bind ${config.toh.meta.network.ip}
                hosts {
                  ${builtins.concatStringsSep "\n" (
                    map (m: "${m.config.toh.meta.network.ip} ${m.name}.${nodeDomain}") machines
                  )}
                  fallthrough
                }
              }

              ${serviceDomain} {
                bind 127.0.0.1
                bind ${config.toh.meta.network.ip}
                template IN A {
                  ${tohLib.strings.indentTail "    " (
                    builtins.concatStringsSep "\n" (
                      builtins.map (relay: ''answer "{{ .Name }} 60 IN A ${relay}"'') relays
                    )
                  )}
                }
              }

              . {
                bind 127.0.0.1
                bind ${config.toh.meta.network.ip}
                forward . ${builtins.concatStringsSep " " cfg.forwarders}
              }
            '';
          };
        })
      ];
    };
}
