{
  lib,
  config,
  tohLib,
  ...
}:

let
  allOverlays = config.toh.overlays;

  composedAllOverlays = tohLib.overlay.composeOverlayAttrs allOverlays allOverlays;

  composedDefaultAllOverlay = tohLib.overlay.composeOverlay allOverlays allOverlays;
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

    self.nixpkgs.overlays = [ composedDefaultAllOverlay ];
  };
}
