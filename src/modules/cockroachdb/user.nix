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
      cfg = config.toh.services.cockroachdb;

      serviceCfg = config.services.cockroachdb;

      user = config.toh.meta.user.user;

      machineName = config.toh.meta.machine.name;

      clientCerts =
        builtins.replaceStrings [ "~" ] [ config.users.users.${user}.home ]
          tohLib.cockroachdb.certs.user;

      clientEnv = "${clientCerts}/user.env";

      machines = tohLib.serviceMachines "cockroachdb";

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
    {
      options.toh.services = {
        cockroachdb = {
          connectUser = lib.mkEnableOption "CockroachDB user connection" // {
            default = tohLib.anyServiceMachines "cockroachdb";
          };
        };
      };

      config = lib.mkIf cfg.connectUser {
        # TODO: fix recursion here
        # toh.overlays.cli-cockroachdb-user = (
        #   tohLib.cli.makeOverlay {
        #     extraRuntimeInputs = pkgs: [
        #       pkgs.cockroachdb
        #       pkgs.vault
        #     ];
        #     loadExtraTextFromFile = ./user.nu;
        #     extraTextVariables = {
        #       TOH_COCKROACHDB_USER_ENV_PATH = clientEnv;
        #     };
        #   }
        # );

        services.cockroachdb.init.sql.files = lib.mkBefore [
          config.sops.secrets."cockroach-${user}-init".path
        ];

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
        sops.secrets."cockroach-${user}-init" = {
          owner = user;
          group = user;
          mode = "0400";
        };

        toh.cryl.machine.cockroachdb-user = {
          generations = [
            {
              generator = "copy";
              arguments = {
                from = "cluster/cockroach-${user}-pass";
                to = "cockroach-${user}-pass";
              };
            }
            {
              generator = "cockroach-client-cert";
              arguments = {
                ca_private = "cluster/cockroach-ca-private";
                ca_public = "cluster/cockroach-ca-public";
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
                    COCKROACH_USER_PASS = "cluster/cockroach-${user}-pass";
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
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-${user}-init";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_USER_PASS = "cluster/cockroach-${user}-pass";
                  };
                };
                template = ''
                  create user if not exists ${user} password '{{COCKROACH_USER_PASS}}';

                  create database if not exists ${user};

                  use ${user};

                  alter default privileges for all roles in schema public grant all on tables to ${user};
                  alter default privileges for all roles in schema public grant all on sequences to ${user};
                  alter default privileges for all roles in schema public grant all on functions to ${user};

                  grant all on all tables in schema public to ${user};
                  grant all on all sequences in schema public to ${user};
                  grant all on all functions in schema public to ${user};

                  reset database;
                '';
              };
            }
          ];
        };

        # FIXME: this only runs after cockroachdb-ca because it is alphabetically ordered after it
        toh.cryl.cluster.cockroachdb-user = {
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
        };

        toh.services.cockroachdb.installCa = true;
        toh.services.cockroachdb.createUserGroup = true;
      };
    };
}
