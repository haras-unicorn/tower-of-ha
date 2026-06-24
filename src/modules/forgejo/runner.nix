{
  toh.lib.nixosModules.services-forgejo-runner =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo.runner;

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-http.endpoint;

      owner = "forgejo-runner";
      group = "forgejo-runner";
    in
    {
      options.toh.services.forgejo = {
        runner = {
          enable = lib.mkEnableOption "Forgejo Actions runner";

          labels = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "self-hosted:host" ];
            defaultText = lib.literalExpression ''[ "self-hosted:host" ]'';
            description = ''
              Labels used to match workflow jobs to this runner.
              Host mode executes steps directly without container isolation.
            '';
            example = [
              "self-hosted:host"
              "linux-amd64:host"
            ];
          };

          capacity = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1;
            description = "Maximum number of concurrent jobs this runner can process.";
          };

          hostPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = with pkgs; [
              bash
              coreutils
              curl
              gawk
              git
              git-lfs
              gnused
              nodejs
              wget
            ];
            description = "Packages available to host-mode workflow steps.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.gitea-actions-runner = {
          package = pkgs.forgejo-actions-runner;

          instances.forgejo = {
            enable = true;
            name = config.toh.meta.machine.name;
            url = "https://${proxyAttrs.host}";
            tokenFile = config.toh.meta.sops.secrets."forgejo-runner-token".path;
            labels = cfg.labels;
            hostPackages = cfg.hostPackages;
            settings = {
              runner = {
                inherit (cfg) capacity;
                labels = cfg.labels;
                timeout = "3h";
                insecure = false;
              };
              container = {
                network = "host";
              };
            };
          };
        };

        toh.meta.sops.secrets."forgejo-runner-token" = {
          user = owner;
          group = group;
          key = "forgejo-runner-token";
          mode = "0400";
          path = "/etc/forgejo-runner/token";
          restartUnits = [ "gitea-runner-forgejo.service" ];
        };

        users.groups.${group} = { };
        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };

        toh.meta.cryl.machine = [
          {
            forgejo-runner = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-runner-token";
                    to = "forgejo-runner-token";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
