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
      forgejoEnabled = config.toh.services.forgejo.enable;
      forgejoPkg = config.services.forgejo.package;
      forgejoCfgFile = "/run/secrets/forgejo-config";

      owner = "forgejo-runner";
      group = "forgejo-runner";

      configDir = "/var/lib/forgejo-runner";
      configFile = "${configDir}/config.yaml";
      runnerFile = "${configDir}/.runner";

      forgejoUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.forgejo.endpoint { };

      secretPath = config.toh.meta.sops.secrets."forgejo-runner-secret".path;
      secretDir = builtins.dirOf secretPath;
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

        toh.meta.cryl.machine = [
          {
            forgejo-runner = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "forgejo-runner-secret";
                    length = 40;
                  };
                }
              ];
            };
          }
        ];

        systemd.services.forgejo-runner-register = lib.mkIf forgejoEnabled {
          description = "Forgejo Runner Registration";
          after = [ "forgejo.service" ];
          requires = [ "forgejo.service" ];
          wantedBy = [ "multi-user.target" ];
          path = [ forgejoPkg ];

          script = ''
              set -euo pipefail

              SECRET=$(cat "${secretPath}")
              NAME="${config.toh.meta.machine.name}"

              UUID=$(forgejo --config "${forgejoCfgFile}" forgejo-cli actions register \
                --name "$NAME" \
                --scope all \
                --secret "$SECRET")

              mkdir -p "${configDir}"

              cat > "${configFile}" <<EOF
            log:
              level: info
              job_level: info

            runner:
              file: "${runnerFile}"
              capacity: 1
              timeout: 3h
              insecure: false
              labels:
                - self-hosted:host

            cache:
              enabled: false

            host:
              workdir_parent:

            server:
              connections:
                forgejo:
                  url: "${forgejoUrl}"
                  uuid: $UUID
                  token_url: "file:${secretPath}"
            EOF

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

        systemd.services.forgejo-runner = {
          description = "Forgejo Actions Runner";
          after = [
            "network-online.target"
          ]
          ++ lib.optional forgejoEnabled "forgejo-runner-register.service";
          requires = lib.optional forgejoEnabled "forgejo-runner-register.service";
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            HOME = configDir;
            CREDENTIALS_DIRECTORY = secretDir;
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
