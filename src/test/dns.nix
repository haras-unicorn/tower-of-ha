{
  toh.lib.test.testModules.dns =
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

      config = lib.mkIf testConfig.toh.test.dns.enable {
        defaults = (
          { config, nodes, ... }:
          lib.mkIf (config.toh.meta.machine.name != "dns" && config.toh.test.network.enable) (
            lib.mkMerge [
              (lib.mkIf config.toh.services.coredns.enable {
                toh.services.coredns.forwarders = lib.mkForce [ nodes.dns.toh.meta.network.ip ];
              })
              (lib.mkIf (!config.toh.services.coredns.enable) {
                networking.nameservers = lib.mkForce [ nodes.dns.toh.meta.network.ip ];
              })
            ]
          )
        );

        toh.test.commands.prefix = lib.mkBefore ''
          dns.wait_for_unit("coredns.service")
        '';

        nodes.dns =
          { config, ... }:
          {
            services.coredns = {
              enable = true;
              config =
                let
                  zoneBlocks = lib.mapAttrsToList (zone: records: ''
                    ${zone} {
                      hosts {
                        ${lib.concatStringsSep "\n" (
                          lib.mapAttrsToList (
                            name: ips:
                            let
                              ipList = if builtins.isList ips then ips else [ ips ];
                            in
                            lib.concatMapStrings (ip: "${ip} ${name}") ipList
                          ) records
                        )}
                        fallthrough
                      }
                    }
                  '') testConfig.toh.test.dns.zones;
                in
                lib.concatStringsSep "\n" zoneBlocks;
            };

            networking.firewall.allowedUDPPorts = [ port ];
            networking.firewall.allowedTCPPorts = [ port ];
          };
      };
    };
}
