{ inputs, ... }:

{
  toh.overlays.unstable = {
    deps = [
      "apply-patches"
      "packages"
    ];
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
        tohPackages = prev.tohPackages // {
          unstablePackages = import unstableNixpkgs {
            inherit (final) system;
            overlays = final.overlays;
            config = {
              allowUnfree = true;
            };
          };
        };
      };
  };
}
