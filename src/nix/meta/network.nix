{
  self.nixosModules.meta-network.flake = true;
  self.nixosModules.meta-network.value =
    { lib, ... }:
    {
      options.toh.meta = {
        network = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = ''
              Machine LAN address.
            '';
          };
          interface = lib.mkOption {
            type = lib.types.str;
            description = ''
              Machine network interface.
            '';
          };

          holePunchers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Names of processes that punch holes through NAT. Others reach
              their UDP ports through the connections they start themselves,
              not through the firewall, so these ports stay closed in it.
            '';
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
    };
}
