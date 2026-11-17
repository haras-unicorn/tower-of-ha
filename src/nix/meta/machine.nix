{
  self.nixosModules.meta-machine.flake = true;
  self.nixosModules.meta-machine.value =
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
