{ config, lib, ... }:

let
  tohLib = config.toh.lib;

  flakeLib = lib.filterAttrsRecursive (_: value: value ? _tohFlakeLib && value._tohFlakeLib) tohLib;

  recursiveAttrsOf =
    elemType:
    lib.types.mkOptionType {
      name = "recursiveAttrsOf";
      description = "nested attribute set of ${elemType.description or "values"}";
      descriptionClass = "noun";
      check = value: lib.isAttrs value;
      merge = loc: defs: lib.foldl' lib.recursiveUpdate { } (builtins.map (def: def.value) defs);
    };
in
{
  options.toh = {
    lib = lib.mkOption {
      type = recursiveAttrsOf lib.types.raw;
      description = "ToH library merged attrset";
      default = { };
    };
  };

  config = {
    _module.args.tohLib = tohLib;
    perSystem._module.args.tohLib = tohLib;

    flake.lib = flakeLib;

    toh.lib.types.recursiveAttrsOf = recursiveAttrsOf;
  };
}
