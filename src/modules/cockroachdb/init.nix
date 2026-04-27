{ ... }:

{
  toh.lib.nixosModules.services-cockroachdb-init =
    {
      lib,
      tohLib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.services.cockroachdb;

      crdb = cfg.package;

      certs = cfg.certsDir;

      databaseUrl =
        "postgresql://"
        + "root"
        + "@${cfg.sql.address}"
        + ":${builtins.toString cfg.sql.port}"
        + "?sslmode=verify-full"
        + "&sslrootcert=${certs}/ca.crt"
        + "&sslcert=${certs}/client.root.crt"
        + "&sslkey=${certs}/client.root.key";
    in
    {
      options.services.cockroachdb = {
        init = {
          enable = lib.mkEnableOption "CockroachDB initialization";

          hash = lib.mkOption {
            type = lib.types.str;
            description = "Current initialization hash";
          };

          packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages to include in the init script";
          };

          sql = {
            scripts = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of SQL scripts (as strings) to execute during initialization";
            };

            files = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ ];
              description = "List of SQL file paths to execute during initialization";
            };
          };

          nushell = {
            scripts = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of nushell scripts (as strings) to execute during initialization (init node only)";
            };

            files = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ ];
              description = "List of nushell script file paths to execute during initialization (init node only)";
            };
          };
        };
      };

      config = lib.mkIf (cfg.enable && cfg.init.enable) {
        toh.overlays = {
          cockroachdb-init-package = tohLib.cli.makeBaseOverlay "cockroachdb-init";
          cockroachdb-init = tohLib.cli.makeFinalOverlay "cockroachdb-init";
          cockroachdb-init-impl = tohLib.cli.makeOverrideOverlay "cockroachdb-init" {
            extraRuntimeInputs = pkgs: [
              pkgs.postgresql
              pkgs.util-linux
              crdb
            ];
            loadExtraTextFromFile = ./init.nu;
            extraTextVariables =
              let
                host = "${cfg.listen.address}:${builtins.toString cfg.listen.port}";
              in
              {
                TOH_DATABASE_INIT_HOST = host;
                TOH_DATABASE_INIT_USER = config.systemd.services.cockroachdb.serviceConfig.User;
                TOH_DATABASE_INIT_CERTS_DIR = cfg.certsDir;
                TOH_DATABASE_INIT_DATABASE_URL = databaseUrl;
                TOH_DATABASE_INIT_HASH = cfg.init.hash;
                TOH_DATABASE_INIT_COMMAND = "cockroach init --host ${host} --certs-dir ${cfg.certsDir}";
                TOH_DATABASE_INIT_SQL_SCRIPTS = "${builtins.concatStringsSep "," (
                  cfg.init.sql.files
                  ++ (lib.imap1 (
                    i: sql: pkgs.writeText "cockroach-sql-${builtins.toString i}.sql" sql
                  ) cfg.init.sql.scripts)
                )}";
                TOH_DATABASE_INIT_NUSHELL_SCRIPTS = "${builtins.concatStringsSep "," (
                  cfg.init.nushell.files
                  ++ (lib.imap1 (
                    i: script: pkgs.writeText "cockroach-nushell-${builtins.toString i}.sh" script
                  ) cfg.init.nushell.scripts)
                )}";
              };
          };
        };

        systemd.services.cockroachdb-initialization = {
          description = "CockroachDB Initialization";
          wantedBy = [ "cockroachdb.service" ];
          bindsTo = [ "cockroachdb.service" ];
          after = [ "cockroachdb.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
            ExecStart = lib.getExe pkgs.tohPackages.cockroachdb-init;
          };
        };
      };
    };
}
