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
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        perSystem =
          {
            pkgs,
            lib,
            ...
          }:
          let
            flake-root = pkgs.writeShellApplication {
              name = "flake-root";
              text = ''
                current="$PWD"
                while [[ "$current" != "/" ]]; do
                  if [[ -f "$current/flake.nix" ]]; then
                    echo "$current"
                    exit 0
                  fi
                  current="$(dirname "$current")"
                done
                echo "no flake.nix found" >&2
                exit 1
              '';
            };

            externalPackages = with pkgs; [
              nil
              nixfmt-rfc-style

              markdownlint-cli
              nodePackages.markdown-link-check
              marksman

              nodePackages.cspell

              mdbook
              nodePackages.prettier
              nodePackages.vscode-langservers-extracted
              nodePackages.prettier
              nodePackages.yaml-language-server
              taplo

              fd
              delta
              cachix
            ];

            scripts = {
              format = ''
                cd "$(flake-root)"

                prettier --write .

                # shellcheck disable=SC2046
                nixfmt $(fd '.*.nix$' .)
              '';
              lint = ''
                cd "$(flake-root)"

                prettier --check .

                cspell lint . --no-progress

                # shellcheck disable=SC2046
                nixfmt --check $(fd '.*.nix$' .)

                markdownlint --ignore-path .markdownignore .
                if [[ -z "''${NIX_BUILD_TOP:-}" ]]; then
                  # shellcheck disable=SC2046
                  markdown-link-check \
                    --config .markdown-link-check.json \
                    --quiet \
                    $(fd '.*.md' .)
                fi
              '';
            };

            scriptPackages = builtins.map (
              { name, value }:
              pkgs.writeShellApplication {
                name = "dev-${name}";
                runtimeInputs = externalPackages ++ [ flake-root ];
                text = value;
              }
            ) (lib.attrsToList scripts);
          in
          {
            nix-unit.inputs = inputs;

            packages.docs =
              pkgs.runCommand "docs"
                {
                  src = self;
                  nativeBuildInputs = [ pkgs.mdbook ];
                }
                ''
                  mdbook build -d "$out" "$src/docs"
                '';

            devShells.default = pkgs.mkShell {
              packages = externalPackages ++ scriptPackages;
            };

            checks.default =
              pkgs.runCommand "checks-default"
                {
                  src = self;
                  nativeBuildInputs = externalPackages ++ [ flake-root ];
                }
                ''
                  cd "$src"
                  ${scripts.lint}
                  touch "$out"
                '';
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
