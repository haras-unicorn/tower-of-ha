{
  self,
  tohLib,
  lib,
  ...
}:

{
  toh.overlays.cli-toh = tohLib.cli.makeOverlay {
    extraTextDir = ./.;
    extraTextVariables = {
      TOH_VERSION = lib.trim (builtins.readFile "${self}/VERSION.txt");
    };
  };
}
