{ inputs, self, ... }:

{
  imports = [
    inputs.nix-unit.modules.flake.default
  ];

  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      externalPackages = with pkgs; [
        git
        tohPackages.flake-root

        nil
        nixfmt-rfc-style
        nix-unit

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

      cli = pkgs.tohPackages.cli.override (prev: {
        name = "dev-toh";
        extraRuntimeInputs = prev.extraRuntimeInputs ++ externalPackages;
        extraText =
          prev.extraText
          + (builtins.concatStringsSep "\n\n" (
            builtins.map (script: builtins.readFile (lib.path.append ./. script)) (
              builtins.filter (lib.hasSuffix ".nu") (builtins.attrNames (builtins.readDir ./.))
            )
          ));
      });
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
        packages = externalPackages ++ [ cli ];
      };

      checks.default =
        pkgs.runCommand "checks-default"
          {
            src = self;
            nativeBuildInputs = externalPackages ++ [ cli ];
          }
          ''
            cd "$src"
            dev-toh lint
            touch "$out"
          '';
    };
}
