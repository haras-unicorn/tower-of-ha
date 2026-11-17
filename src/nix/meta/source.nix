{
  toh.lib.nixosModules.meta-source =
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
