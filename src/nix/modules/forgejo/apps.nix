{ selfLib, ... }:

{
  self.nixosModules.services-forgejo-apps.flake = true;
  self.nixosModules.services-forgejo-apps.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      owner = "forgejo";
      group = "forgejo";

      anyMachines = selfLib.cluster.anyServiceMachines config "forgejo";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
          }
        ) (lib.attrsToList apps);

      machineApps = appAttrsToList config.toh.meta.git.apps;

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.git.apps) config.toh.meta.cluster.machineList
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));

      users = builtins.map (
        { name, ... }:
        {
          inherit name;
          email = "${name}@${config.toh.meta.email.domain}";
          password = config.toh.meta.sops.secrets."forgejo-app-${name}-pass".path;
        }
      ) clusterApps;

      script = pkgs.tohPackages.writeNushellApplication {
        name = "forgejo-apps";
        runtimeInputs = [ config.services.forgejo.package ];
        text = pkgs.harasPackages.renderMustacheText {
          name = "forgejo-apps-text";
          text = builtins.readFile ./apps.nu;
          vars = {
            TOH_FORGEJO_CONFIG = cfg.config.path;
            TOH_FORGEJO_USERS = builtins.toJSON users;
          };
        };
      };
    in
    {
      options.toh.services.forgejo.apps.retrySeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = ''
          Seconds between tries to create the git users of the apps, which fail
          until Forgejo has set up its database.
        '';
      };

      config = {
        toh.meta.git.users = mergeByMachineApps (
          { name, ... }:
          {
            ${name} = {
              inherit name;
              password = config.toh.meta.sops.secrets."forgejo-user-${name}-pass".path;
            };
          }
        );

        systemd.services.forgejo-apps = lib.mkIf (cfg.enable && clusterApps != [ ]) {
          description = "Forgejo git users of the apps";
          after = [ "forgejo.service" ];
          requires = [ "forgejo.service" ];
          wantedBy = [ "toh-git-online.target" ];
          before = [ "toh-git-online.target" ];
          unitConfig.StartLimitIntervalSec = 0;
          environment.HOME = config.services.forgejo.stateDir;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = owner;
            Group = group;
            Restart = "on-failure";
            RestartSec = cfg.apps.retrySeconds;
          };
          script = lib.getExe script;
        };

        toh.meta.sops.secrets = lib.mkMerge [
          (mergeByClusterApps (
            { name, ... }:
            {
              "forgejo-app-${name}-pass" = {
                inherit owner group;
                mode = "0400";
              };
            }
          ))
          (mergeByMachineApps (
            { name, ... }@app:
            {
              "forgejo-user-${name}-pass" = {
                owner = app.user;
                group = app.group;
                mode = "0400";
              };
            }
          ))
        ];

        toh.meta.cryl.machine = lib.mkMerge [
          (mergeByClusterApps (
            { name, ... }:
            [
              {
                "forgejo-app-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/forgejo-${name}-pass";
                        to = "forgejo-app-${name}-pass";
                      };
                    }
                  ];
                };
              }
            ]
          ))
          (mergeByMachineApps (
            { name, ... }:
            [
              {
                "forgejo-user-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/forgejo-${name}-pass";
                        to = "forgejo-user-${name}-pass";
                      };
                    }
                  ];
                };
              }
            ]
          ))
        ];

        toh.meta.cryl.cluster = mergeByClusterApps (
          { name, ... }:
          [
            {
              "forgejo-${name}" = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "forgejo-${name}-pass";
                    };
                  }
                ];
              };
            }
          ]
        );
      };
    };
}
