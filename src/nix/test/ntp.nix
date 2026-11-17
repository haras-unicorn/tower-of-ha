{
  toh.lib.test.testModules.ntp =
    {
      lib,
      config,
      nodes,
      pkgs,
      ...
    }:
    let
      port = 123;
    in
    {
      options.toh.test = {
        ntp = {
          enable = lib.mkEnableOption "NTP test server";
        };
      };

      config = lib.mkIf config.toh.test.ntp.enable {
        defaults =
          { config, nodes, ... }:
          lib.mkIf (config.toh.meta.machine.name != "ntp" && config.toh.test.network.enable) {
            networking.timeServers = lib.mkForce [ nodes.ntp.toh.meta.network.ip ];
          };

        toh.test.commands.prefix = lib.mkBefore ''
          ntp.wait_for_unit("chronyd.service")
        '';

        nodes.ntp =
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
      };
    };
}
