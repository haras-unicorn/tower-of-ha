{ selfLib, ... }:

{
  self.nixosModules.services-samba-apps.flake = true;
  self.nixosModules.services-samba-apps.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.samba;

      anyMachines = selfLib.cluster.anyServiceMachines config "samba";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
          }
        ) (lib.attrsToList apps);

      machineApps = appAttrsToList config.toh.meta.share.apps;

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.share.apps) config.toh.meta.cluster.machineList
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
          password = config.toh.meta.sops.secrets."samba-app-${name}-pass".path;
        }
      ) clusterApps;

      script = pkgs.tohPackages.writeNushellApplication {
        name = "samba-apps";
        runtimeInputs = [ config.services.samba.package ];
        text = pkgs.harasPackages.renderMustacheText {
          name = "samba-apps-text";
          text = builtins.readFile ./apps.nu;
          vars = {
            TOH_SAMBA_USERS = builtins.toJSON users;
          };
        };
      };
    in
    {
      options.toh.services.samba.apps = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = "/srv/share";
          description = ''
            Where the Samba machines mount the files of the shares of the
            apps, one directory per app.
          '';
        };

        retrySeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = ''
            Seconds between tries to set the Samba passwords of the apps,
            which fail until the Samba directories exist.
          '';
        };
      };

      config = {
        toh.meta.share.shares = mergeByMachineApps (
          { name, ... }:
          {
            ${name} = {
              inherit name;
              user = name;
              password = config.toh.meta.sops.secrets."samba-user-${name}-pass".path;
            };
          }
        );

        users.groups = mergeByClusterApps ({ name, ... }: { ${name} = { }; });
        users.users = mergeByClusterApps (
          { name, ... }:
          {
            ${name} = {
              isSystemUser = true;
              group = name;
            };
          }
        );

        toh.meta.filesystem.mounts = mergeByClusterApps (
          { name, ... }:
          {
            "${cfg.apps.directory}/${name}" = {
              user = name;
              group = name;
              share.name = name;
            };
          }
        );

        # NOTE: smbd keeps its passwords in a tdb file on CephFS, which only
        # one machine may write at a time, so the lease holder sets them
        toh.leases = lib.mkIf (cfg.enable && clusterApps != [ ]) {
          samba.services = [ "samba-users" ];
        };

        systemd.services.samba-users = lib.mkIf (cfg.enable && clusterApps != [ ]) {
          description = "Samba users of the apps";
          after = [ "samba-dirs.service" ];
          requires = [ "samba-dirs.service" ];
          before = [ "samba-smbd.service" ];
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = cfg.apps.retrySeconds;
          };
          script = lib.getExe script;
        };

        toh.meta.sops.secrets = lib.mkMerge [
          (mergeByClusterApps (
            { name, ... }:
            {
              "samba-app-${name}-pass" = {
                mode = "0400";
              };
            }
          ))
          (mergeByMachineApps (
            { name, ... }@app:
            {
              "samba-user-${name}-pass" = {
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
                "samba-app-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/samba-${name}-pass";
                        to = "samba-app-${name}-pass";
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
                "samba-user-${name}-pass" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/samba-${name}-pass";
                        to = "samba-user-${name}-pass";
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
              "samba-${name}" = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "samba-${name}-pass";
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
