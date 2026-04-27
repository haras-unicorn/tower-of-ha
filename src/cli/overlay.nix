{ self, tohLib, ... }:

{
  toh.overlays.cli-toh = tohLib.cli.makeOverlay {
    loadExtraTextFromDir = ./.;
    extraTextVariables = {
      TOH_VERSION = builtins.readFile "${self}/VERSION.txt";
    };
  };
}
