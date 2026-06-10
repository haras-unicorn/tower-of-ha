{
  description = "Highly opinionated, free and highly available service stack";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    cryl.url = "github:haras-unicorn/cryl/refs/tags/v0.4.1";
    cryl.inputs.nixpkgs.follows = "nixpkgs";
    cryl.inputs.flake-parts.follows = "flake-parts";
    cryl.inputs.import-tree.follows = "import-tree";
    cryl.inputs.sops-nix.follows = "sops-nix";

    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./src);

  nixConfig = {
    extra-substituters = [
      "https://haras.cachix.org"
    ];
    extra-trusted-public-keys = [
      "haras.cachix.org-1:/HIo1JYqOIH1Nwk1EGXhuPPvDW0WekxIbY5CiXUZbYw="
    ];
  };
}
