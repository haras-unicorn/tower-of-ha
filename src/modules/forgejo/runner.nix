{
  toh.lib.nixosModules.services-forgejo-runner =
    {
      lib,
      config,
      pkgs,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.forgejo.runner;

      owner = "forgejo-runner";
      group = "forgejo-runner";

      stateDir = "/var/lib/forgejo-runner";
      configFile = "/run/secrets/forgejo-runner-config";
      runnerFile = "${stateDir}/.runner";

      machineName = config.toh.meta.machine.name;
      machinea = builtins.filter (
        machine: machine.config.toh.services.forgejo.runner.enable
      ) config.toh.meta.cluster.machinea;

      forgejoUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.forgejo.endpoint { };

      secretPath = config.toh.meta.sops.secrets."forgejo-runner-secret".path;

      dbInstance = config.toh.meta.database.instances.forgejo;

      yamlFormat = pkgs.formats.yaml { };
      configTemplate = yamlFormat.generate "forgejo-runner-config" {
        log = {
          level = "info";
          job_level = "info";
        };
        runner = {
          file = runnerFile;
          capacity = 1;
          timeout = "3h";
          insecure = false;
          labels = [ "self-hosted:host" ];
        };
        cache.enabled = false;
        host.workdir_parent = null;
        server.connections.forgejo = {
          url = forgejoUrl;
          uuid = "{{{TOH_FORGEJO_RUNNER_ID}}}";
          token = "{{{TOH_FORGEJO_RUNNER_SECRET}}}";
        };
      };
    in
    {
      options.toh.services.forgejo = {
        runner = {
          enable = lib.mkEnableOption "Forgejo Actions runner";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.overlays = tohLib.cli.makeOverlays {
          name = "forgejo-runner";
          runtimeInputs = pkgs: [
            pkgs.usql
            pkgs.tohPackages.mustacheRenderer
          ];
          textFile = ./runner.nu;
          textVariables = {
            TOH_FORGEJO_RUNNER_CONFIG_TEMPLATE = configTemplate;
            TOH_FORGEJO_RUNNER_CONFIG_PATH = configFile;
            TOH_FORGEJO_RUNNER_SECRET = secretPath;
            TOH_FORGEJO_RUNNER_MACHINE_NAME = machineName;
            TOH_FORGEJO_RUNNER_USER = owner;
            TOH_FORGEJO_RUNNER_GROUP = group;
            TOH_FORGEJO_RUNNER_DB_INSTANCE = dbInstance;
          };
        };

        systemd.services.forgejo-runner-config = {
          path = [ pkgs.tohPackages.forgejo-runnner ];
          script = "forgejo-runner";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = owner;
            Group = group;
            SupplementaryGroups = "forgejo-config";
          };
        };

        systemd.services.forgejo-runner = {
          description = "Forgejo Actions Runner";
          after = [ "forgejo-runner-config.service" ];
          requires = [ "forgejo-runner-config.service" ];
          environment = {
            HOME = stateDir;
          };
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.forgejo-runner} daemon --config ${configFile}";
            User = owner;
            Group = group;
            StateDirectory = builtins.baseNameOf stateDir;
            WorkingDirectory = stateDir;
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        users.groups.${group} = { };
        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };

        toh.meta.sops.secrets."forgejo-runner-secret" = {
          inherit owner group;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            "forgejo-runner" = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-runner-machine-${machineName}-secret";
                    to = "forgejo-runner-secret";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            "forgejo-runners" = {
              generations = builtins.map (machine: {
                generator = "key";
                arguments = {
                  name = "forgejo-runner-machine-${machine.name}-secret";
                  length = 40;
                };
              }) machinea;
            };
          }
        ];
      };
    };
}
