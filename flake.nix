{
  description = "Highly opinionated, free and highly available service stack";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    cryl.url = "github:haras-unicorn/cryl";
    cryl.inputs.nixpkgs.follows = "nixpkgs";
    cryl.inputs.flake-parts.follows = "flake-parts";
    cryl.inputs.import-tree.follows = "import-tree";
    cryl.inputs.sops-nix.follows = "sops-nix";

    comin.url = "github:nlewo/comin/refs/tags/v0.8.0";
    comin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = {
          root = ./.;
        };
      }
      {
        imports = [
          inputs.nix-unit.modules.flake.default
          (inputs.import-tree ./src)
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        perSystem =
          { system, ... }:
          let
            originalPkgs = import inputs.nixpkgs {
              inherit system;
            };

            nixpkgs = self.lib.nixpkgs.patch originalPkgs;
          in
          {
            _module.args.pkgs = import nixpkgs {
              system = originalPkgs.stdenv.hostPlatform.system;
              overlays = [ self.overlays.default ];
              config = {
                allowUnfree = true;
              };
            };
          };
      };

  nixConfig = {
    extra-substituters = [
      "https://haras.cachix.org"
    ];
    extra-trusted-public-keys = [
      "haras.cachix.org-1:/HIo1JYqOIH1Nwk1EGXhuPPvDW0WekxIbY5CiXUZbYw="
    ];
  };
}
