{
  toh.lib.nixosModules.services-miniflux =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.miniflux;

      user = config.toh.meta.user.user;
      minifluxUser = "miniflux_${config.toh.meta.machine.name}";
      certs = "/etc/miniflux/certs";
      # NOTE: 8080 is cockroachdb, 8081 is seaweedfs
      port = 8082;
      package = pkgs.miniflux.overrideAttrs (
        final: prev: {
          patches = (prev.patches or [ ]) ++ [
            ./cockroach-fixes.patch
          ];
        }
      );
      package-admin = pkgs.writeShellApplication {
        name = "miniflux-admin";
        runtimeInputs = [
          package
          pkgs.coreutils
        ];
        text = ''
          if [ "$EUID" -ne 0 ]; then
            echo "Please run as root"
            exit 1
          fi

          set -o allexport
          # shellcheck source=/dev/null
          source "${config.sops.secrets."miniflux-env".path}"
          set +o allexport
          exec miniflux "$@"
        '';
      };
    in
    {
      options.toh.services = {
        miniflux = {
          enable = lib.mkEnableOption "Miniflux";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          package-admin
        ];

        services.miniflux.enable = true;
        services.miniflux.package = package;
        services.miniflux.createDatabaseLocally = false;
        services.miniflux.config = {
          LISTEN_ADDR = "0.0.0.0:${builtins.toString port}";
          RUN_MIGRATIONS = 1;
          CREATE_ADMIN = 1;
          BASE_URL = "https://miniflux.${config.toh.meta.domains.service}/";
        };
        # NOTE: its named adminCredentialsFile but its just an EnvironmentFile setting
        services.miniflux.adminCredentialsFile = config.sops.secrets."miniflux-env".path;

        users.users.miniflux = {
          group = "miniflux";
          description = "Miniflux service user";
          isSystemUser = true;
        };
        users.groups.miniflux = { };
        systemd.services.miniflux = {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "miniflux";
            Group = "miniflux";
          };
        };

        services.cockroachdb.init.sql.files = [ config.sops.secrets."cockroach-miniflux-init".path ];
        systemd.services.miniflux.wantedBy = [ "toh-database-initialized.target" ];
        systemd.services.miniflux.requires = [ "toh-database-initialized.target" ];
        systemd.services.miniflux.after = [ "toh-database-initialized.target" ];

        networking.firewall.allowedTCPPorts = [ port ];

        toh.meta.services = [
          {
            name = "miniflux";
            port = port;
            health = "http:///healthcheck";
          }
        ];

        sops.secrets."miniflux-env" = {
          owner = config.systemd.services.miniflux.serviceConfig.User;
          group = config.systemd.services.miniflux.serviceConfig.User;
          mode = "0400";
        };
        sops.secrets."cockroach-miniflux-init" = {
          owner = config.systemd.services.cockroachdb.serviceConfig.User;
          group = config.systemd.services.cockroachdb.serviceConfig.User;
          mode = "0400";
        };
        sops.secrets."cockroach-miniflux-ca-public" = {
          key = "cockroach-ca-public";
          path = "${certs}/ca.crt";
          owner = config.systemd.services.miniflux.serviceConfig.User;
          group = config.systemd.services.miniflux.serviceConfig.User;
          mode = "0644";
        };
        sops.secrets."cockroach-miniflux-public" = {
          path = "${certs}/client.miniflux.crt";
          owner = config.systemd.services.miniflux.serviceConfig.User;
          group = config.systemd.services.miniflux.serviceConfig.User;
          mode = "0644";
        };
        sops.secrets."cockroach-miniflux-private" = {
          path = "${certs}/client.miniflux.key";
          owner = config.systemd.services.miniflux.serviceConfig.User;
          group = config.systemd.services.miniflux.serviceConfig.User;
          mode = "0400";
        };

        toh.cryl.machine.miniflux = {
          generations = [
            {
              generator = "copy";
              arguments = {
                from = "cluster/${user}-password";
                to = "${user}-password";
              };
            }
            {
              generator = "cockroach-client";
              arguments = {
                renew = true;
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                private = "cockroach-miniflux-private";
                public = "cockroach-miniflux-public";
                user = minifluxUser;
              };
            }
            {
              generator = "key";
              arguments = {
                name = "cockroach-miniflux-pass";
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-miniflux-init";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_MINIFLUX_PASS = "cockroach-miniflux-pass";
                  };
                };
                template = ''
                  create user if not exists ${minifluxUser} password '{{COCKROACH_MINIFLUX_PASS}}';
                  create database if not exists miniflux;

                  \c miniflux
                  alter default privileges for all roles in schema public grant all on tables to ${minifluxUser};
                  alter default privileges for all roles in schema public grant all on sequences to ${minifluxUser};
                  alter default privileges for all roles in schema public grant all on functions to ${minifluxUser};

                  grant all on all tables in schema public to ${minifluxUser};
                  grant all on all sequences in schema public to ${minifluxUser};
                  grant all on all functions in schema public to ${minifluxUser};

                  alter default privileges for all roles in schema public grant all on tables to ${user};
                  alter default privileges for all roles in schema public grant all on sequences to ${user};
                  alter default privileges for all roles in schema public grant all on functions to ${user};

                  grant all on all tables in schema public to ${user};
                  grant all on all sequences in schema public to ${user};
                  grant all on all functions in schema public to ${user};

                  -- NOTE: needed for migrations
                  grant create on database miniflux to ${minifluxUser};
                  grant create on schema public to ${minifluxUser};
                '';
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "miniflux-env";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_MINIFLUX_PASS = "cockroach-miniflux-pass";
                    ADMIN_PASSWORD = "${user}-password";
                  };
                };
                template =
                  let
                    databaseUrl =
                      "postgresql://${minifluxUser}:{{COCKROACH_MINIFLUX_PASS}}@localhost"
                      + ":${builtins.toString config.services.cockroachdb.listen.port}"
                      + "/miniflux"
                      + "?sslmode=verify-full"
                      + "&sslrootcert=${certs}/ca.crt"
                      + "&sslcert=${certs}/client.miniflux.crt"
                      + "&sslkey=${certs}/client.miniflux.key";
                  in
                  ''
                    DATABASE_URL="${databaseUrl}"
                    ADMIN_USERNAME="${user}"
                    ADMIN_PASSWORD="{{ADMIN_PASSWORD}}"
                  '';
              };
            }
          ];
        };
      };
    };
}
