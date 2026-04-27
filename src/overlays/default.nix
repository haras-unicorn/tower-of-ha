{
  lib,
  config,
  tohLib,
  ...
}:

let
  allOverlays = config.toh.overlays;

  flakeOverlays = lib.filterAttrs (_: { flake, ... }: flake) allOverlays;

  composedAllOverlays = tohLib.overlay.composeOverlayAttrs allOverlays allOverlays;

  composedDefaultAllOverlay = tohLib.overlay.composeOverlay allOverlays allOverlays;

  composedFlakeOverlays = tohLib.overlay.composeOverlayAttrs allOverlays flakeOverlays;

  composedDefaultFlakeOverlay = tohLib.overlay.composeOverlay allOverlays flakeOverlays;
in
{
  options.toh = {
    overlays = lib.mkOption {
      default = { };
      description = "Attrset of ToH overlays with dependencies";
      type = lib.types.attrsOf (tohLib.types.overlay);
    };
  };

  config = {
    toh.lib.overlays =
      let
        noUndefinedDepsAssertion = tohLib.overlay.makeUndefinedDepsAssertion allOverlays;
      in
      assert lib.assertMsg noUndefinedDepsAssertion.assertion noUndefinedDepsAssertion.message;
      (
        composedAllOverlays
        // {
          default = composedDefaultAllOverlay;
        }
      );

    flake.overlays =
      let
        noUndefinedDepsAssertion = tohLib.overlay.makeUndefinedDepsAssertion allOverlays;
      in
      assert lib.assertMsg noUndefinedDepsAssertion.assertion noUndefinedDepsAssertion.message;
      (
        composedFlakeOverlays
        // {
          default = composedDefaultFlakeOverlay;
        }
      );
  };
}
