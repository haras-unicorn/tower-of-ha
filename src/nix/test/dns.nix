{ selfLib, ... }:

{
  self.lib.test.testModules.dns =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      testConfig = config;

      port = 53;
    in
    {
      options.toh.test = {
        dns = {
          enable = lib.mkEnableOption "DNS test server";

          zones = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.str
                  (lib.types.listOf lib.types.str)
                ]
              )
            );
            default = { };
            description = "Local DNS zones to serve as static records";
            example = {
              "test.local" = {
                "test.local" = "192.168.1.100";
                "www.test.local" = "192.168.1.100";
              };
            };
          };
        };
      };

      config = lib.mkIf testConfig.toh.test.dns.enable (
        lib.mkMerge [
          {
            defaults = (
              {
                config,
                nodes,
                containers,
                ...
              }:
              let
                dnsIp = (nodes // containers).dns.toh.meta.network.ip;
              in
              lib.mkIf (config.toh.meta.machine.name != "dns" && testConfig.toh.test.network.enable) (
                lib.mkMerge [
                  (lib.mkIf config.toh.services.coredns.enable {
                    toh.services.coredns.forwarders = lib.mkForce [ dnsIp ];
                  })
                  # NOTE: a machine of a cluster with CoreDNS asks that, so the
                  # tests see the answers the cluster gives, and CoreDNS asks
                  # the helper only for what it forwards
                  (lib.mkIf
                    (!config.toh.services.coredns.enable && !(selfLib.cluster.anyServiceMachines config "coredns"))
                    {
                      networking.nameservers = lib.mkForce [ dnsIp ];
                    }
                  )
                ]
              )
            );

            toh.test.commands.prefix = lib.mkBefore ''
              dns.wait_for_unit("coredns.service")
            '';
          }
          (selfLib.test.ofKind testConfig.toh.test.kind {
            dns = {
              # NOTE: the helper is a machine of the cluster to ToH but does not
              # trust its CA, so it could not get a token from a secrets service
              toh.services.openbao.token.enable = false;

              services.coredns = {
                enable = true;
                config =
                  let
                    makeRecord =
                      name: ip:
                      let
                        type = if lib.hasInfix ":" ip then "AAAA" else "A";
                      in
                      "${name}. 60 IN ${type} ${ip}";

                    # NOTE: zone files and not the hosts plugin, because hosts
                    # has no SOA record, so it answers a name it does not
                    # have with a server failure, and clients that look up
                    # optional records, like Matrix servers looking for SRV
                    # records, take that as an error
                    makeZoneFile =
                      zone: records:
                      pkgs.writeText "${zone}.zone" ''
                        $ORIGIN ${zone}.
                        @ 60 IN SOA dns.${zone}. hostmaster.${zone}. 1 60 60 60 60
                        @ 60 IN NS dns.${zone}.
                        ${lib.concatStringsSep "\n" (
                          lib.mapAttrsToList (
                            name: ips:
                            let
                              ipList = if builtins.isList ips then ips else [ ips ];
                            in
                            lib.concatMapStringsSep "\n" (makeRecord name) ipList
                          ) records
                        )}
                      '';

                    zoneBlocks = lib.mapAttrsToList (zone: records: ''
                      ${zone} {
                        file ${makeZoneFile zone records}
                      }
                    '') testConfig.toh.test.dns.zones;
                  in
                  lib.concatStringsSep "\n" zoneBlocks;
              };

              networking.firewall.allowedUDPPorts = [ port ];
              networking.firewall.allowedTCPPorts = [ port ];
            };
          })
        ]
      );
    };
}
