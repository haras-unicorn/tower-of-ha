{ selfLib, ... }:

{
  self.nixosModules.services-synapse-apps.flake = true;
  self.nixosModules.services-synapse-apps.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.synapse;

      anyMachines = selfLib.cluster.anyServiceMachines config "synapse";

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.synapse.endpoint;

      owner = "matrix-synapse";
      group = "matrix-synapse";

      chatName = app: "toh-${app}";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
          }
        ) (lib.attrsToList apps);

      machineApps = appAttrsToList config.toh.meta.chat.apps;

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.chat.apps) config.toh.meta.cluster.machineList
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));

      runsApps = cfg.enable && clusterApps != [ ];

      script = pkgs.tohPackages.writeNushellApplication {
        name = "synapse-apps";
        runtimeInputs = [ config.services.matrix-synapse.package ];
        text = pkgs.harasPackages.renderMustacheText {
          name = "synapse-apps-text";
          text = builtins.readFile ./apps.nu;
          vars = {
            TOH_SYNAPSE_APPS = builtins.toJSON {
              url = "http://${config.toh.meta.network.ip}:${builtins.toString cfg.port}";
              config = cfg.config.path;
              users = builtins.map (
                { name, ... }:
                {
                  name = chatName name;
                  alias = chatName name;
                  password = config.toh.meta.sops.secrets."synapse-app-${name}-pass".path;
                }
              ) clusterApps;
            };
          };
        };
      };
    in
    {
      options.toh.services.synapse.apps.retrySeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = ''
          Seconds between tries to make the chat users and rooms of the apps,
          which fail until Synapse is up.
        '';
      };

      config = {
        toh.meta.chat.users = mergeByMachineApps (
          { name, ... }:
          {
            ${name} = {
              name = chatName name;
              password = config.toh.meta.sops.secrets."synapse-user-${name}-pass".path;
              room = "#${chatName name}:${proxyAttrs.host}";
            };
          }
        );

        # NOTE: users and rooms are made through the main process, so the
        # lease holder makes them
        toh.leases = lib.mkIf runsApps {
          synapse.services = [ "synapse-apps" ];
        };

        systemd.services.synapse-apps = lib.mkIf runsApps {
          description = "Synapse chat users and rooms of the apps";
          after = [ "matrix-synapse.service" ];
          requires = [ "matrix-synapse.service" ];
          unitConfig.StartLimitIntervalSec = 0;
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
              "synapse-app-${name}-pass" = {
                inherit owner group;
                mode = "0400";
              };
            }
          ))
          (mergeByMachineApps (
            { name, ... }@app:
            {
              "synapse-user-${name}-pass" = {
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
                "synapse-app-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/synapse-${name}-pass";
                        to = "synapse-app-${name}-pass";
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
                "synapse-user-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/synapse-${name}-pass";
                        to = "synapse-user-${name}-pass";
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
              "synapse-${name}" = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "synapse-${name}-pass";
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
