{ tohLib, ... }:

{
  toh.lib.test.testModules.lib =
    { config, lib, ... }:
    {
      options.toh = {
        lib = lib.mkOption {
          type = tohLib.types.recursiveAttrsOf lib.types.raw;
          default = { };
          description = "ToH library merged attrset";
        };
      };

      config = {
        _module.args.tohLib = config.toh.lib;

        toh.lib = tohLib;
      };
    };
}
