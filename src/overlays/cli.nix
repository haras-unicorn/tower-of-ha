{ tohLib, ... }:

{
  toh.overlays.cli-package = tohLib.cli.makeBaseOverlay "cli";

  toh.overlays.cli-name = tohLib.cli.makeOverrideOverlay "cli" {
    name = "toh";
  };

  toh.overlays.cli = tohLib.cli.makeFinalOverlay "cli";
}
