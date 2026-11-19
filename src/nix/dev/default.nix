{
  self.devShells.default = {
    flake = true;

    value =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        yaml = pkgs.formats.yaml { };

        toml = pkgs.formats.toml { };

        json = pkgs.formats.json { };

        prettierConfig = yaml.generate "prettier.yaml" {
          printWidth = 80;
          tabWidth = 2;
          useTabs = false;
          trailingComma = "all";
          endOfLine = "lf";
          proseWrap = "always";
        };

        markdownlintConfig = json.generate "markdownlint.json" {
          "$schema" =
            "https://raw.githubusercontent.com/DavidAnson/markdownlint/main/schema/markdownlint-config-schema.json";
        };

        markdownLinkCheckConfig = json.generate "markdown-link-check.json" {
          ignorePatterns = [
            { pattern = "^#"; }
            { pattern = "^https://localhost"; }
            { pattern = "^http://localhost"; }
            { pattern = "^https://haras-unicorn.github.io/tower-of-ha"; }
            { pattern = "^https://github.com/haras-unicorn/tower-of-ha"; }
          ];
        };

        helixServers = lib.mapAttrs (
          _: server:
          {
            inherit (server) command;
          }
          // lib.optionalAttrs (server.arguments != [ ]) {
            args = server.arguments;
          }
          // lib.optionalAttrs (server.config != { }) {
            inherit (server) config;
          }
        ) config.languages.servers;

        helixLanguages = lib.mapAttrsToList (
          name: language:
          {
            inherit name;
            auto-format = language.auto-format;
          }
          // lib.optionalAttrs (language.servers != [ ]) {
            language-servers = language.servers;
          }
          // lib.optionalAttrs (language.formatter != null) {
            formatter = {
              inherit (language.formatter) command;
            }
            // lib.optionalAttrs (language.formatter.arguments != [ ]) {
              args = language.formatter.arguments;
            };
          }
        ) config.languages.languages;

        helixLanguagesToml = toml.generate "languages.toml" (
          lib.optionalAttrs (helixServers != { }) {
            language-server = helixServers;
          }
          // lib.optionalAttrs (helixLanguages != [ ]) {
            language = helixLanguages;
          }
        );

        nixfmtWrapped = pkgs.harasPackages.makeBubblewrapWrapper {
          name = "nixfmt";
          package = pkgs.nixfmt;
        };

        prettierWrapped = pkgs.harasPackages.makeBubblewrapWrapper {
          name = "prettier";
          package = pkgs.prettier;
        };

        taploWrapped = pkgs.harasPackages.makeBubblewrapWrapper {
          name = "taplo";
          package = pkgs.taplo;
        };

        cspellWrapped = pkgs.harasPackages.makeBubblewrapWrapper {
          name = "cspell";
          package = pkgs.cspell;
        };

        hxWrapped = pkgs.harasPackages.makeBubblewrapWrapper {
          name = "hx";
          package = pkgs.helix;
          files = {
            "~/.cache/helix" = {
              mode = "rw";
            };
            ".helix/languages.toml" = {
              mode = "ro";
              source = helixLanguagesToml;
            };
          };
        };

        # NOTE: these two need kvm or a kernel that is not out yet, so a
        # plain `dev test` leaves them out; naming them runs them
        skippedTests = [
          "services-cephfs-kernel-mount"
          "services-chronyd-clock"
        ];

        testRunner = pkgs.harasPackages.writeNushellApplication {
          name = "dev-test";
          runtimeInputs = [ pkgs.nix ];
          text = pkgs.harasPackages.renderMustacheText {
            name = "dev-test-text";
            text = builtins.readFile ./test.nu;
            vars = {
              skippedJson = builtins.toJSON skippedTests;
            };
          };
        };

        external = [
          pkgs.nil
          pkgs.nix

          pkgs.nushell
          pkgs.bashInteractive
          pkgs.fd
          pkgs.mdbook
          pkgs.delta
          pkgs.cachix

          pkgs.yaml-language-server
          pkgs.vscode-langservers-extracted
          pkgs.markdownlint-cli
          pkgs.markdown-link-check
          pkgs.marksman
          pkgs.treefmt
        ];
      in
      {
        packages = [
          pkgs.harasPackages.flake-root
          nixfmtWrapped
          prettierWrapped
          taploWrapped
          cspellWrapped
          hxWrapped
        ]
        ++ external;

        git = {
          enable = true;
          ignore = {
            templates = [ "Nix" ];
            patterns = ''
              # Repository

              .env
              docs/book
              **/.nixos-test-history
            '';
          };
          attributes = ''
            * text=auto eol=lf
          '';
        };

        direnv = {
          enable = true;
          extra = "dotenv_if_exists .env";
        };

        editorconfig = {
          enable = true;
          settings."*" = {
            end_of_line = "lf";
            charset = "utf-8";
            max_line_length = 80;
            indent_style = "space";
            indent_size = 2;
            tab_width = 2;
            insert_final_newline = true;
            trim_trailing_whitespace = true;
          };
        };

        languages = {
          servers = {
            nil.command = "nil";

            taplo = {
              command = "taplo";
              arguments = [
                "lsp"
                "stdio"
              ];
            };

            yaml-language-server = {
              command = "yaml-language-server";
              arguments = [ "--stdio" ];
            };

            marksman = {
              command = "marksman";
              arguments = [ "server" ];
            };

            nu-lsp = {
              command = "nu";
              arguments = [ "--lsp" ];
            };

            vscode-json-language-server = {
              command = "vscode-json-language-server";
              arguments = [ "--stdio" ];
              config = {
                provideFormatter = true;
                format.enable = true;
                json.validate.enable = true;
              };
            };
          };

          languages = {
            nix = {
              servers = [ "nil" ];
              formatter = {
                command = lib.getExe pkgs.nixfmt;
                arguments = [
                  "--filename"
                  "%{buffer_name}"
                ];
              };
            };

            toml.servers = [ "taplo" ];

            yaml = {
              servers = [ "yaml-language-server" ];
              formatter = {
                command = lib.getExe pkgs.prettier;
                arguments = [
                  "--config"
                  (builtins.toString prettierConfig)
                  "--parser"
                  "yaml"
                ];
              };
            };

            json = {
              servers = [ "vscode-json-language-server" ];
              formatter = {
                command = lib.getExe pkgs.prettier;
                arguments = [
                  "--config"
                  (builtins.toString prettierConfig)
                  "--parser"
                  "json"
                ];
              };
            };

            markdown = {
              servers = [ "marksman" ];
              formatter = {
                command = lib.getExe pkgs.prettier;
                arguments = [
                  "--config"
                  (builtins.toString prettierConfig)
                  "--parser"
                  "markdown"
                ];
              };
            };

            nu.servers = [ "nu-lsp" ];
          };
        };

        license = {
          enable = true;
          spdx = "MIT";
          path = "LICENSE.md";
          attrs = {
            "<year>" = "2026";
            "<copyright holders>" = "haras-unicorn";
          };
        };

        codeOfConduct.contributorCovenant = {
          enable = true;
          path = "CODE_OF_CONDUCT.md";
        };

        cli.commands = {
          docs = {
            description = "Build the documentation.";
            packages = [ pkgs.nix ];
            commands = ''nix build ".#docs" --no-link --print-out-paths'';
          };

          test = {
            description = "Run the NixOS tests one at a time, or the named ones.";
            packages = [ testRunner ];
            commands = ''dev-test "$@"'';
          };

          check-links = {
            description = "Check Markdown links.";
            packages = [
              pkgs.fd
              pkgs.markdown-link-check
            ];
            commands = ''
              fd --glob '**/*.md' . -0 | xargs -0 -r markdown-link-check \
                --config ${markdownLinkCheckConfig} \
                --quiet
            '';
          };
        };

        workflows = {
          check = {
            on.pull_request = { };

            installable = null;

            steps = [
              { run = "nix develop --command dev check"; }
              { run = "nix flake check"; }
              # NOTE: not a flake check, because evaluating all the tests in
              # one process takes tens of GB
              { run = "nix develop --command dev test"; }
            ];
          };

          docs = {
            on.push.branches = [ "main" ];

            permissions = {
              contents = "read";
              "id-token" = "write";
              pages = "write";
            };

            installable = ".#docs";

            steps = [
              {
                uses = "actions/upload-pages-artifact@v3";
                "with".path = "./result";
              }
              { uses = "actions/deploy-pages@v4"; }
            ];
          };

          release-pr = {
            on.push.branches = [ "main" ];

            permissions = {
              contents = "write";
              "pull-requests" = "write";
            };

            installable = null;
            installNix = false;
            cachix = null;

            steps = [
              {
                uses = "googleapis/release-please-action@v4";
                "with" = {
                  command = "manifest";
                  token = "\${{ secrets.RELEASE_PLEASE_TOKEN }}";
                  "config-file" = ".release-please-config.json";
                  "manifest-file" = ".release-please-manifest.json";
                  "default-branch" = "main";
                };
              }
            ];
          };

          update = {
            on = {
              schedule = [ { cron = "0 6 * * 1"; } ];
              workflow_dispatch = { };
            };

            permissions = {
              contents = "write";
              "pull-requests" = "write";
            };

            installable = null;

            steps = [
              { run = "nix flake update"; }
              {
                uses = "peter-evans/create-pull-request@v6";
                "with" = {
                  token = "\${{ secrets.UPDATE_TOKEN }}";
                  body = "Automated flake.lock update.";
                  branch = "ci/update-flake-lock";
                  "commit-message" = "chore: update flake.lock";
                  title = "chore: update flake.lock";
                };
              }
            ];
          };
        };

        check.checks = {
          cspell = {
            packages = [ cspellWrapped ];
            commands = "cspell lint . --no-progress";
          };

          markdownlint = {
            packages = [ pkgs.markdownlint-cli ];
            commands = ''
              markdownlint --config ${markdownlintConfig} \
                --ignore-path .gitignore \
                --ignore CHANGELOG.md \
                --ignore LICENSE.md \
                .
            '';
          };

          nil = {
            packages = [
              pkgs.fd
              pkgs.nil
            ];
            commands = ''
              status=0
              output="$(fd --glob '*.nix' . -0 | xargs -0 -r nil diagnostics 2>&1)" || status=$?
              if [ -n "$output" ]; then
                printf '%s\n' "$output" >&2
                status=1
              fi
              test "$status" -eq 0
            '';
          };
        };

        format.formatters = {
          nixfmt = {
            packages = [ nixfmtWrapped ];
            command = "nixfmt";
            includes = [ "*.nix" ];
          };

          taplo = {
            packages = [ taploWrapped ];
            command = "taplo";
            options = [ "format" ];
            includes = [ "*.toml" ];
          };

          prettier = {
            packages = [ prettierWrapped ];
            command = "prettier";
            options = [
              "--write"
              "--config"
              (builtins.toString prettierConfig)
            ];
            includes = [
              "*.json"
              "*.md"
              "*.yaml"
              "*.yml"
            ];
            excludes = [
              "flake.lock"
              ".release-please-manifest.json"
              "CHANGELOG.md"
              "LICENSE.md"
            ];
          };
        };
      };
  };
}
