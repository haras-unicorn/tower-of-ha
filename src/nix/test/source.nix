{ self, ... }:

{
  toh.lib.test.testModules.source =
    { lib, ... }:
    {
      options.toh.test = {
        source = {
          flake = lib.mkOption {
            type = lib.types.str;
            description = "Flake of the ToH cluster source code";
          };
          hash = lib.mkOption {
            type = lib.types.str;
            description = "Hash of the ToH cluster source code";
          };
        };
      };

      config = {
        toh.test.source = {
          flake = "path:${self}";
          hash = "test";
        };

        defaults = {
          toh.meta.source = {
            flake = "path:${self}";
            hash = "test";
          };
        };
      };
    };
}
