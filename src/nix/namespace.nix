{ inputs, ... }:

{
  self.nixpkgs.overlays = [ inputs.haraspkgs.overlays.default ];

  self.overlays.namespace = "tohPackages";
}
