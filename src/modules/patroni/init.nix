{
  toh.lib.nixosModules.services-patroni-init =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.patroni;
    in
    {
      options.toh.services = {
        patroni = {
          init = {
            enable = lib.mkEnableOption "Patroni cluster initialization";

            hash = lib.mkOption {
              type = lib.types.str;
              default = config.toh.meta.source.hash;
              description = "Current initialization hash";
            };

            packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "Packages to include in the init script";
            };

            sql = {
              scripts = lib.mkOption {
                type = lib.types.listOf (lib.types.attrsOf lib.types.str);
                default = [ ];
                description = "List of SQL scripts (as strings) to execute during initialization";
              };

              files = lib.mkOption {
                type = lib.types.listOf (lib.types.attrsOf lib.types.path);
                default = [ ];
                description = "List of SQL file paths to execute during initialization";
              };
            };

            nushell = {
              scripts = lib.mkOption {
                type = lib.types.listOf (lib.types.attrsOf lib.types.str);
                default = [ ];
                description = "List of nushell scripts (as strings) to execute during initialization (init node only)";
              };

              files = lib.mkOption {
                type = lib.types.listOf (lib.types.attrsOf lib.types.path);
                default = [ ];
                description = "List of nushell script file paths to execute during initialization (init node only)";
              };
            };

            systemd = {
              units = lib.mkOption {
                type = lib.types.listOf (lib.types.attrsOf lib.types.str);
                default = [ ];
                description = "List of systemd units to execute during initialization (init node only)";
              };
            };
          };
        };
      };

      config = lib.mkIf cfg.init.enable {
        toh.overlays = {
          patroni-init-package = tohLib.cli.makeBaseOverlay "patroni-init";
          patroni-init = tohLib.cli.makeFinalOverlay "patroni-init";
          patroni-init-impl = tohLib.cli.makeOverrideOverlay "patroni-init" {
            extraRuntimeInputs = pkgs: [
              config.services.patroni.postgresqlPackage
              pkgs.patroni
            ];
            extraTextFile = ./init.nu;
            extraTextVariables =
              let
                serializeScripts =
                  { files, scripts }:
                  let
                    fileList = tohLib.lists.concatMapUniqueAttrValues (
                      { name, value }:
                      {
                        inherit name;
                        path = value;
                      }
                    ) files;
                    scriptList = tohLib.lists.concatMapUniqueAttrValues (
                      { name, value }:
                      {
                        inherit name;
                        path = pkgs.writeText "${name}.sql" value;
                      }
                    ) scripts;
                  in
                  fileList ++ scriptList;

                sqlScripts = serializeScripts cfg.init.sql;
                nushellScripts = serializeScripts cfg.init.nushell;

                systemdUnits = tohLib.lists.concatMapUniqueAttrValues (
                  { name, value }:
                  {
                    inherit name;
                    unit = value;
                  }
                ) cfg.init.systemd.units;

                initPasswordSql = builtins.concatStringsSep "\n" (
                  lib.mapAttrsToList (
                    key: name:
                    let
                      passwordFile = cfg.users.${name}.password;
                    in
                    ''alter user ${name} with password '(open --raw "${passwordFile}")';''
                  ) tohLib.patroni.superusers
                );
              in
              {
                TOH_DATABASE_INIT_HASH = cfg.init.hash;
                TOH_DATABASE_INIT_COMMAND = ''
                  with-env {
                    PGPASSWORD: null
                  } {
                    psql -c $"
                      ${tohLib.strings.indentTail "    " initPasswordSql}
                    "
                  }
                '';
                TOH_DATABASE_INIT_DATABASE_ENV_FILE = cfg.users.${tohLib.patroni.superusers.superuser}.env;
                TOH_DATABASE_INIT_SQL_SCRIPTS = "${builtins.toJSON sqlScripts}";
                TOH_DATABASE_INIT_NUSHELL_SCRIPTS = "${builtins.toJSON nushellScripts}";
                TOH_DATABASE_INIT_SYSTEMD_UNITS = "${builtins.toJSON systemdUnits}";
              };
          };
        };

        # NOTE: running as root because we need to be able to run other services from this
        systemd.services.patroni-initialization = {
          description = "patroni Initialization";
          wantedBy = [ "patroni.service" ];
          bindsTo = [ "patroni.service" ];
          after = [ "patroni.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
            ExecStart = lib.getExe pkgs.tohPackages.patroni-init;
          };
        };

        systemd.targets.toh-database-initialized = {
          bindsTo = [ "patroni-initialization.service" ];
          after = [ "patroni-initialization.service" ];
        };

        toh.services.patroni.users.${tohLib.patroni.superusers.superuser}.installSecrets = true;
      };
    };
}
