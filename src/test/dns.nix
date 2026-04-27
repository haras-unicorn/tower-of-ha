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
            description = "Local DNS zones to serve as local-data entries";
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
          lib.mkIf (config.toh.meta.machine.name != "dns" && config.toh.test.network.enable) {
            networking.nameservers = lib.mkForce [ nodes.dns.toh.meta.network.ip ];
          }
        );

        toh.test.commands.prefix = lib.mkBefore ''
          dns.wait_for_unit("unbound.service")
        '';

        nodes.dns =
          { config, ... }:
          {
            services.unbound = {
              enable = true;
              settings = {
                server = lib.mkMerge [
                  {
                    interface = [ "0.0.0.0" ];
                    port = port;
                    access-control = [
                      "192.168.0.0/16 allow"
                      "${config.toh.meta.network.subnet.ip}/${builtins.toString config.toh.meta.network.subnet.bits} allow"
                    ];
                  }
                  (lib.mkIf (testConfig.toh.test.dns.zones != { }) {
                    "local-zone" = lib.mapAttrsToList (name: _: "${name} static") testConfig.toh.test.dns.zones;
                    "local-data" = lib.flatten (
                      lib.mapAttrsToList (
                        _: records:
                        lib.mapAttrsToList (
                          name: ips:
                          let
                            ipList = if builtins.isList ips then ips else [ ips ];
                          in
                          builtins.map (ip: "\"${name}. A ${ip}\"") ipList
                        ) records
                      ) testConfig.toh.test.dns.zones
                    );
                  })
                ];
              };
            };

            networking.firewall.allowedUDPPorts = [ port ];
            networking.firewall.allowedTCPPorts = [ port ];
          };
      };
    };
}
