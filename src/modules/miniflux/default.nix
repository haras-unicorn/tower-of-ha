# NOTE: this service is incomplete and requires to be tested thoroughly!!!
# please do not take into account anything in this service file or its test file

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

      port = 8082;

      database = config.toh.meta.database;
      instance = database.instances.miniflux;
      envPath = "/var/lib/${config.systemd.services.miniflux.serviceConfig.StateDirectory}/toh.env";
      owner = config.systemd.services.miniflux.User;
      group = config.systemd.services.miniflux.Group;
    in
    {
      options.toh.services = {
        miniflux = {
          enable = lib.mkEnableOption "Miniflux";
        };
      };

      config = lib.mkIf cfg.enable {
        services.miniflux.enable = true;
        services.miniflux.createDatabaseLocally = false;
        services.miniflux.config = {
          LISTEN_ADDR = "${config.toh.meta.network.ip}:${builtins.toString port}";
          RUN_MIGRATIONS = 1;
          CREATE_ADMIN = 1;
          BASE_URL = "https://miniflux.${config.toh.meta.domains.service}/";
        };
        services.miniflux.adminCredentialsFile = envPath;
        systemd.services.vault.serviceConfig.ExecStartPre = ''
          ${lib.getExe pkgs.tohPackages.mustacheRenderer} \
            --variables '{
              "DATABASE_MINIFLUX_URL": "${instance.url}",
              "ADMIN_PASSWORD": "${config.sops.secrets."miniflux-admin-password".path}"
            }' \
            --template 'DATABASE_URL="{{DATABASE_MINIFLUX_URL}}"
          ADMIN_USERNAME="miniflux"
          ADMIN_PASSWORD="{{ADMIN_PASSWORD}}"
          ' \
            --out "${envPath}" \
            --chmod 400 \
            --chown "${owner}:${group}"
        '';

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

        systemd.services.miniflux.wantedBy = [ "toh-database-initialized.target" ];
        systemd.services.miniflux.requires = [ "toh-database-initialized.target" ];
        systemd.services.miniflux.after = [ "toh-database-initialized.target" ];

        networking.firewall.allowedTCPPorts = [ port ];

        toh.meta.services.miniflux = {
          endpoint.http.port = port;
          health.endpoint.http.path = "healthcheck";
        };

        toh.meta.database.apps.miniflux = {
          user = config.systemd.services.miniflux.serviceConfig.User;
          group = config.systemd.services.miniflux.serviceConfig.User;
        };

        sops.secrets."miniflux-admin-password" = {
          inherit owner group;
          mode = "0400";
        };

        toh.cryl.machine = [
          {
            miniflux = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/miniflux-admin-password";
                    to = "miniflux-admin-password";
                  };
                }
              ];
            };
          }
        ];

        toh.cryl.cluster = [
          {
            miniflux = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "miniflux-admin-password";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
