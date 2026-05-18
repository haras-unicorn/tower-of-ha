{
  toh.lib.nixosModules.meta-machine =
    { lib, ... }:
    {
      options.toh.meta = {
        machine = {
          name = lib.mkOption {
            type = lib.types.str;
            description = ''
              Name of the machine.
            '';
          };
          index = lib.mkOption {
            type = lib.types.ints.unsigned;
            description = ''
              Machine index.
            '';
          };
          version = lib.mkOption {
            type = lib.types.str;
            description = ''
              Machine system version.
            '';
          };
        };
      };
    };
}
