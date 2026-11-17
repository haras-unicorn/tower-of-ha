{ lib, config, ... }:

{
  # NOTE: config.self.lib and not selfLib, because selfLib depends on every
  # overlay through the flake assertions of haraspkgs
  self.overlays.overlays = lib.mkMerge [
    (config.self.lib.cli.makeOverlays {
      attr = "cli";
      name = "toh";
    })
    { cli.flake = true; }
  ];
}
