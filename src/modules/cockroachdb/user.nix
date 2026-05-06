{
  toh.lib.nixosModules.services-cockroachdb-user =
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

      user = config.toh.meta.user.user;

      machineName = config.toh.meta.machine.name;

      clientCerts = "${config.users.users.${user}.home}/.cockroach-certs";

      clientEnv = "${clientCerts}/user.env";

      machines = tohLib.serviceMachines "cockroachdb";

      anyMachines = tohLib.anyServiceMachines "cockroachdb";

      cockroachHost =
        if config.toh.cockroachdb.enable then
          "${serviceCfg.sql.address}:${builtins.toString serviceCfg.sql.port}"
        else if machines == [ ] then
          lib.warn "No hosts for cockroachdb detected" ""
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
    in
    lib.mkMerge [
      {
        toh.overlays.cli-cockroachdb-user = (
          tohLib.cli.makeOverlay {
            enable = anyMachines;
            extraRuntimeInputs = pkgs: [
              pkgs.cockroachdb
              pkgs.vault
            ];
            loadExtraTextFromFile = ./user.nu;
            extraTextVariables = {
              TOH_COCKROACHDB_USER_ENV_PATH = clientEnv;
            };
          }
        );
      }

      (lib.mkIf anyMachines {
        sops.secrets."cockroach-${user}-ca-public" = {
          key = "cockroach-ca-public";
          path = "${clientCerts}/ca.crt";
          owner = user;
          group = user;
          mode = "0644";
        };
        sops.secrets."cockroach-${machineName}-${user}-public" = {
          path = "${clientCerts}/client.${user}.crt";
          owner = user;
          group = user;
          mode = "0644";
        };
        sops.secrets."cockroach-${machineName}-${user}-private" = {
          path = "${clientCerts}/client.${user}.key";
          owner = user;
          group = user;
          mode = "0400";
        };
        sops.secrets."cockroach-${user}-env" = {
          path = clientEnv;
          owner = user;
          group = user;
          mode = "0400";
        };

        toh.cryl.machine.cockroachdb-user-pass = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-${user}-pass";
                to = "cockroach-${user}-pass";
              };
            }
          ];
        };

        toh.cryl.machine.cockroachdb-user = {
          generations = [
            {
              generator = "cockroach-client-cert";
              arguments = {
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                private = "cockroach-${machineName}-${user}-private";
                public = "cockroach-${machineName}-${user}-public";
                user = user;
                renew = true;
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-${user}-env";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_USER_PASS = "cockroach-${user}-pass";
                  };
                };
                template =
                  let
                    url =
                      "postgresql://${user}:{{COCKROACH_USER_PASS}}@${cockroachHost}"
                      + "?sslmode=verify-full"
                      + "&sslrootcert=${clientCerts}/ca.crt"
                      + "&sslcert=${clientCerts}/client.${user}.crt"
                      + "&sslkey=${clientCerts}/client.${user}.key";
                  in
                  ''
                    export COCKROACH_URL="${url}"

                    export PGUSER="${user}"
                    export PGPASSWORD="{{COCKROACH_USER_PASS}}"
                    export PGHOST="${postgresHost}"
                    export PGSSLMODE="verify-full"
                    export PGSSLROOTCERT="${clientCerts}/ca.crt"
                    export PGSSLCERT="${clientCerts}/client.${user}.crt"
                    export PGSSLKEY="${clientCerts}/client.${user}.key"
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
        toh.cryl.cluster.cockroachdb-user = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-${user}-pass";
                to = "cockroach-${user}-pass";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-${user}-private";
                to = "cockroach-${user}-private";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/cockroach-${user}-public";
                to = "cockroach-${user}-public";
                allow_fail = true;
              };
            }
          ];
          generations = [
            {
              generator = "key";
              arguments = {
                name = "cockroach-${user}-pass";
              };
            }
            {
              generator = "cockroach-client-cert";
              arguments = {
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                private = "cockroach-${user}-private";
                public = "cockroach-${user}-public";
                user = user;
                renew = true;
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-${user}-pass";
                to = "${tohLib.secrets.directories.cluster}/cockroach-${user}-pass";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-${user}-private";
                to = "${tohLib.secrets.directories.cluster}/cockroach-${user}-private";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-${user}-public";
                to = "${tohLib.secrets.directories.cluster}/cockroach-${user}-public";
              };
            }
          ];
        };
      })
    ];
}
