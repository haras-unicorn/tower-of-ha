{ lib, ... }:

{
  toh.lib.types.testCommand = lib.types.oneOf [
    lib.types.lines
    (lib.types.listOf lib.types.str)
    (lib.types.functionTo (lib.types.either lib.types.lines (lib.types.listOf lib.types.str)))
  ];
}
