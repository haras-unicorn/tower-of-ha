{
  toh.lib.test.testModules.network =
    { lib, ... }:
    {
      options.toh.test = {
        network = {
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

      config = {
        toh.test.network.subnet = {
          prefix = "10.69.42";
          ip = "10.69.42.0";
          bits = 24;
          mask = "255.255.255.0";
        };

        defaults = {
          toh.meta.network.subnet = {
            prefix = "10.69.42";
            ip = "10.69.42.0";
            bits = 24;
            mask = "255.255.255.0";
          };
        };
      };
    };
}
