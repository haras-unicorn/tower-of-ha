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
      serviceCfg = config.services.cockroachdb;

      envPath = "/etc/cockroachdb/root.env";

      certs = "/var/lib/cockroachdb/.certs";

      machines = tohLib.serviceMachines "cockroachdb";

      anyMachines = tohLib.anyServiceMachines "cockroachdb";

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
    lib.mkMerge [
      {
        toh.overlays.cli-cockroachdb-root = (
          tohLib.cli.makeOverlay {
            enable = anyMachines;
            extraRuntimeInputs = pkgs: [
              pkgs.cockroachdb
              pkgs.vault
            ];
            loadExtraTextFromFile = ./root.nu;
            extraText = {
              TOH_COCKROACHDB_ROOT_ENV_PATH = envPath;
            };
          }
        );
      }

      (lib.mkIf anyMachines {
        sops.secrets."cockroach-root-ca-public" = {
          key = "cockroach-ca-public";
          path = "${certs}/ca.crt";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0644";
        };
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
          owner = "root";
          group = "root";
          mode = "0400";
        };

        toh.cryl.machine.cockroachdb-root-pass = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-root-pass";
                to = "cockroach-root-pass";
              };
            }
          ];
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
                    COCKROACH_ROOT_PASS = "cockroach-root-pass";
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
          ];
        };

        toh.cryl.machine.cockroachdb-ca = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-ca-private";
                to = "cockroach-ca-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-ca-public";
                to = "cockroach-ca-public";
              };
            }
          ];
        };

        # FIXME: this only runs after cockroachdb-ca because it is alphabetically ordered after it
        toh.cryl.cluster.cockroachdb-root = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-root-pass";
                to = "cockroach-root-pass";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-root-private";
                to = "cockroach-root-private";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-root-public";
                to = "cockroach-root-public";
                allow_fail = true;
              };
            }
          ];
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
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-root-pass";
                to = "${tohLib.secrets.directories.cluster}/cockroach-root-pass";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-root-private";
                to = "${tohLib.secrets.directories.cluster}/cockroach-root-private";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-root-public";
                to = "${tohLib.secrets.directories.cluster}/cockroach-root-public";
              };
            }
          ];
        };
      })
    ];
}
