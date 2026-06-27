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

      configDir = "/var/lib/forgejo-runner";
      configFile = "${configDir}/config.yaml";
      runnerFile = "${configDir}/.runner";

      forgejoUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.forgejo.endpoint { };

      secretPath = config.toh.meta.sops.secrets."forgejo-runner-secret".path;

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
          uuid = "__RUNNER_UUID__";
          token_url = "file:${secretPath}";
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
        toh.meta.sops.secrets."forgejo-runner-secret" = {
          inherit owner group;
          mode = "0400";
        };

        # Copy this machine's runner secret from cluster
        toh.meta.cryl.machine = [
          {
            forgejo-runner = {
              generations = [
                {
                  generator = "script";
                  arguments = {
                    name = "forgejo-runner-secret-script";
                    text = "openssl rand -hex 20 | save -f forgejo-runner-secret";
                  };
                }
              ];
            };
          }
        ];

        # Database access for the runner to look up its UUID
        toh.meta.database.apps.forgejo-runner = {
          user = owner;
          group = group;
          dbName = "forgejo";
          dbUser = "forgejo_runner";
        };

        # Config generator oneshot: fetches UUID from DB, renders config YAML
        systemd.services.forgejo-runner-config = {
          description = "Forgejo Runner Config Generator";
          after = [
            "network-online.target"
            "toh-database-online.target"
          ];
          requires = [
            "network-online.target"
            "toh-database-online.target"
          ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.postgresql ];

          script = ''
            set -euo pipefail

            DB_URL=$(cat "${config.toh.meta.database.instances.forgejo-runner.url}")
            NAME="${config.toh.meta.machine.name}"
            TEMPLATE="${configTemplate}"

            for i in $(seq 1 30); do
              UUID=$(psql $DB_URL -t -A -c "SELECT uuid FROM __toh_action_runners WHERE name = '\$NAME'" 2>/dev/null || echo "")
              if [ -n "$UUID" ]; then
                break
              fi
              echo "Waiting for runner UUID for $NAME (attempt $i/30)..."
              sleep 2
            done

            if [ -z "$UUID" ]; then
              echo "ERROR: Could not get UUID for $NAME after 30 attempts"
              exit 1
            fi

            echo "Got UUID: $UUID for $NAME"

            sed "s|__RUNNER_UUID__|$UUID|g" "$TEMPLATE" > "${configFile}"

            chown ${owner}:${group} "${configFile}"
            chmod 640 "${configFile}"
          '';

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = owner;
            Group = group;
            StateDirectory = "forgejo-runner";
          };
        };

        # Runner daemon
        systemd.services.forgejo-runner = {
          description = "Forgejo Actions Runner";
          after = [
            "network-online.target"
            "forgejo-runner-config.service"
          ];
          requires = [
            "forgejo-runner-config.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            HOME = configDir;
          };

          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.forgejo-runner} daemon --config ${configFile}";
            User = owner;
            Group = group;
            StateDirectory = "forgejo-runner";
            WorkingDirectory = configDir;
            Restart = "on-failure";
            RestartSec = 2;
          };
        };

        users.groups.${group} = { };
        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };
      };
    };
}
