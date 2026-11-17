{
  toh.lib.nixosModules.meta-network =
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
