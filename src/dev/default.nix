{ inputs, self, ... }:

{
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
        nixos-test = ''
          test="$1"
          shift
          nix build \
            ".#checks.$(uname -m)-linux.test-''${test}.withSshBackdoor" \
            --option sandbox-paths /dev/vhost-vsock \
            "$@"
        '';
        nixos-test-interactive = ''
          test="$1"
          shift
          nix run \
            ".#checks.$(uname -m)-linux.test-''${test}.withSshBackdoor.driverInteractive" \
            "$@"
        '';
      };

      scriptPackages = builtins.map (
        { name, value }:
        pkgs.writeShellApplication {
          name = "dev-${name}";
          runtimeInputs = externalPackages;
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
        packages = externalPackages ++ scriptPackages ++ [ cli ];
      };

      checks.default =
        pkgs.runCommand "checks-default"
          {
            src = self;
            nativeBuildInputs = externalPackages;
          }
          ''
            cd "$src"
            ${scripts.lint}
            touch "$out"
          '';
    };
}
