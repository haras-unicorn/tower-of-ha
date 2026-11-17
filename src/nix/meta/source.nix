{
  self.nixosModules.meta-source.flake = true;
  self.nixosModules.meta-source.value =
    { lib, ... }:
    {
      options.toh.meta = {
        source = {
          flake = lib.mkOption {
            type = lib.types.str;
            description = "Source flake URI";
          };
          hash = lib.mkOption {
            type = lib.types.str;
            description = "Source hash";
          };
        };
      };
    };
}
