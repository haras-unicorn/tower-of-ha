{ config, ... }:

let
  tohFlakeConfig = config;
in
{
  toh.lib.nixosModules.meta-overlays =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      allOverlays = config.toh.overlays;

      nixosOverlays = lib.filterAttrs (_: { nixos, ... }: nixos) allOverlays;

      composedAllOverlays = tohLib.overlay.composeOverlayAttrs allOverlays allOverlays;

      composedDefaultAllOverlay = tohLib.overlay.composeOverlay allOverlays allOverlays;

      composedNixpkgsOverlay = tohLib.overlay.composeOverlay allOverlays nixosOverlays;
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
        toh.overlays = tohFlakeConfig.toh.overlays;

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

        nixpkgs.overlays =
          let
            noUndefinedDepsAssertion = tohLib.overlay.makeUndefinedDepsAssertion allOverlays;
          in
          assert lib.assertMsg noUndefinedDepsAssertion.assertion noUndefinedDepsAssertion.message;
          [ composedNixpkgsOverlay ];
      };
    };
}
