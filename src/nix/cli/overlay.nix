{
  self,
  config,
  lib,
  ...
}:

{
  # NOTE: config.self.lib and not selfLib, see overlays/cli.nix
  self.overlays.overlays.cli-toh = config.self.lib.cli.makeOverlay {
    extraTextDir = ./.;
    extraTextVariables = {
      TOH_VERSION = lib.trim (builtins.readFile "${self}/VERSION.txt");
    };
  };
}
