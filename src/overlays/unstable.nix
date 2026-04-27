{ inputs, ... }:

{
  toh.overlays.unstable = {
    deps = [ "apply-patches" ];
    nixos = true;
    value =
      final: prev:
      let
        unstableNixpkgs = final.applyTohNixpkgsPatches {
          name = "nixpkgs-unstable";
          src = inputs.nixpkgs-unstable;
        };
      in
      {
        unstableTohPackages = import unstableNixpkgs {
          inherit (final) system;
          overlays = final.overlays;
          config = {
            allowUnfree = true;
          };
        };
      };
  };
}
