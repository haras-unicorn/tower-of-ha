{
  toh.lib.test.testModules.network =
    { lib, config, ... }:
    let
      cfg = config.toh.test.network;
    in
    {
      options.toh.test = {
        network = {
          enable = lib.mkEnableOption "ToH test network" // {
            default = true;
          };

          subnet = {
            prefix = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet prefix.
              '';
            };
            ip = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet IP.
              '';
            };
            bits = lib.mkOption {
              type = lib.types.ints.u16;
              description = ''
                Network subnet bits.
              '';
            };
            mask = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet mask.
              '';
            };
          };
        };
      };

      config = lib.mkMerge [
        {
          toh.test.network.subnet = lib.mkDefault {
            prefix = "10.69.42";
            ip = "10.69.42.0";
            bits = 24;
            mask = "255.255.255.0";
          };

          defaults = {
            toh.meta.network.subnet = cfg.subnet;
          };
        }
        (lib.mkIf cfg.enable (
          # NOTE: check virtualisation.vlans from man configuration.nix
          let
            vlan = 1;
            vlanString = builtins.toString vlan;
            prefix = "192.168.${vlanString}";
          in
          {
            toh.test.network.subnet = {
              inherit prefix;
              ip = "${prefix}.0";
              bits = 24;
              mask = "255.255.255.0";
            };

            defaults =
              { config, ... }:
              {
                toh.meta.network.ip = prefix + "." + builtins.toString config.virtualisation.test.nodeNumber;
                toh.meta.network.interface = "eth${vlanString}";
                virtualisation.vlans = [ vlan ];
              };
          }
        ))
      ];
    };
}
