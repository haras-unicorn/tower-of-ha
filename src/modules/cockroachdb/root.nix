{
  toh.lib.nixosModules.services-cockroachdb-root =
    {
      lib,
      tohLib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;

      serviceCfg = config.services.cockroachdb;

      certs = tohLib.cockroachdb.certs.root;

      envPath = "${certs}/root.env";

      machines = tohLib.serviceMachines "cockroachdb";

      cockroachHost =
        if config.toh.cockroachdb.enable then
          "${serviceCfg.sql.address}:${builtins.toString serviceCfg.sql.port}"
        else
          let
            machine = builtins.head machines;
            cfg = machine.config.services.cockroachdb;
          in
          "${cfg.sql.address}:${builtins.toString cfg.sql.port}";

      postgresHost =
        if config.toh.cockroachdb.enable then
          "${serviceCfg.sql.address}:${builtins.toString serviceCfg.sql.port}"
        else
          builtins.concatStringsSep "," (
            builtins.map (
              machine:
              let
                cfg = machine.config.services.cockroachdb;
              in
              "${cfg.sql.address}:${builtins.toString cfg.sql.port}"
            ) machines
          );

      machineName = config.toh.meta.machine.name;
    in
    {
      options.toh.services = {
        cockroachdb = {
          connectRoot = lib.mkEnableOption "CockroachDB root connection" // {
            default = tohLib.anyServiceMachines "cockroachdb";
          };
        };
      };

      config = lib.mkIf cfg.connectRoot {
        # TODO: fix recursion here
        # toh.overlays.cli-cockroachdb-root = (
        #   tohLib.cli.makeOverlay {
        #     extraRuntimeInputs = pkgs: [
        #       pkgs.cockroachdb
        #       pkgs.vault
        #     ];
        #     loadExtraTextFromFile = ./root.nu;
        #     extraTextVariables = {
        #       TOH_COCKROACHDB_ROOT_ENV_PATH = envPath;
        #     };
        #   }
        # );

        services.cockroachdb.init.sql.files = lib.mkBefore [
          config.sops.secrets."cockroach-root-init".path
        ];

        sops.secrets."cockroach-root-${machineName}-public" = {
          path = "${certs}/client.root.crt";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0644";
        };
        sops.secrets."cockroach-root-${machineName}-private" = {
          path = "${certs}/client.root.key";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };
        sops.secrets."cockroach-root-env" = {
          path = "${envPath}";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };
        sops.secrets."cockroach-root-init" = {
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };

        toh.cryl.machine.cockroachdb-root = {
          generations = [
            {
              generator = "cockroach-client-cert";
              arguments = {
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                private = "cockroach-root-${machineName}-private";
                public = "cockroach-root-${machineName}-public";
                user = "root";
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-root-env";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_ROOT_PASS = "cluster/cockroach-root-pass";
                  };
                };
                template =
                  let
                    url =
                      "postgresql://root:{{COCKROACH_ROOT_PASS}}@${cockroachHost}"
                      + "?sslmode=verify-full"
                      + "&sslrootcert=${certs}/ca.crt"
                      + "&sslcert=${certs}/client.root.crt"
                      + "&sslkey=${certs}/client.root.key";
                  in
                  ''
                    COCKROACH_URL="${url}"

                    PGUSER="root"
                    PGPASSWORD="{{COCKROACH_ROOT_PASS}}"
                    PGHOST="${postgresHost}"
                    PGSSLMODE="verify-full"
                    PGSSLROOTCERT="${certs}/ca.crt"
                    PGSSLCERT="${certs}/client.root.crt"
                    PGSSLKEY="${certs}/client.root.key"
                  '';
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-root-init";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_ROOT_PASS = "cockroach-root-pass";
                  };
                };
                template = ''
                  alter user root with password '{{COCKROACH_ROOT_PASS}}';
                '';
              };
            }
          ];
        };

        # FIXME: this only runs after cockroachdb-ca because it is alphabetically ordered after it
        toh.cryl.cluster.cockroachdb-root = {
          generations = [
            {
              generator = "key";
              arguments = {
                name = "cockroach-root-pass";
              };
            }
            {
              generator = "cockroach-client-cert";
              arguments = {
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                private = "cockroach-root-private";
                public = "cockroach-root-public";
                user = "root";
              };
            }
          ];
        };

        toh.services.cockroachdb.installCa = true;
        toh.services.cockroachdb.createUserGroup = true;
      };
    };
}
