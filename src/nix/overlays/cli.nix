{ tohLib, ... }:

{
  toh.overlays = tohLib.cli.makeOverlays {
    attr = "cli";
    name = "toh";
  };
}
