{ selfLib, ... }:

{
  self.lib.test.testModules.ntp =
    {
      lib,
      config,
      ...
    }:
    let
      testConfig = config;

      port = 123;
    in
    {
      options.toh.test = {
        ntp = {
          enable = lib.mkEnableOption "NTP test server";
        };
      };

      config = lib.mkIf testConfig.toh.test.ntp.enable (
        lib.mkMerge [
          {
            defaults =
              {
                config,
                nodes,
                containers,
                ...
              }:
              lib.mkIf (config.toh.meta.machine.name != "ntp" && testConfig.toh.test.network.enable) {
                networking.timeServers = lib.mkForce [ (nodes // containers).ntp.toh.meta.network.ip ];
              };

            toh.test.commands.prefix = lib.mkBefore ''
              ntp.wait_for_unit("chronyd.service", timeout=120)
            '';
          }
          (selfLib.test.ofKind testConfig.toh.test.kind {
            ntp =
              { config, ... }:
              {
                services.timesyncd.enable = false;

                services.chrony = {
                  enable = true;
                  servers = [ ];
                  initstepslew.enabled = false;
                  extraConfig = ''
                    local stratum 10
                    allow 192.168.0.0/16
                    allow ${config.toh.meta.network.subnet.ip}/${builtins.toString config.toh.meta.network.subnet.bits}
                    port ${builtins.toString port}
                    log tracking measurements statistics
                  '';
                };

                systemd.services.chronyd.after = [ "network-online.target" ];
                systemd.services.chronyd.requires = [ "network-online.target" ];

                networking.firewall.allowedUDPPorts = [ port ];
              };
          })
        ]
      );
    };
}
