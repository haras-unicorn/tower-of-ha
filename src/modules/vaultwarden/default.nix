{
  toh.lib.nixosModules.services-vaultwarden =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.vaultwarden;

      port = 8222;

      # TODO: remove mention of postgres here
      package = pkgs.vaultwarden-postgresql.overrideAttrs (
        final: prev: {
          patches = (prev.patches or [ ]) ++ [
            ./2020-08-02-025025-migration.patch
            ./specify-integer-length-in-migrations.patch
          ];
        }
      );

      dataDir = "/var/lib/${config.systemd.services.vaultwarden.serviceConfig.StateDirectory}";

      vaultwardenUser = config.systemd.services.vaultwarden.serviceConfig.User;
    in
    {
      options.toh.services = {
        vaultwarden = {
          enable = lib.mkEnableOption "Vaultwarden";
        };
      };

      config = lib.mkIf cfg.enable {
        services.vaultwarden.enable = true;
        services.vaultwarden.package = package;
        # TODO: remove mention of postgres here
        services.vaultwarden.dbBackend = "postgresql";
        services.vaultwarden.config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = port;
          SIGNUPS_ALLOWED = true;
          ENABLE_WEBSOCKET = false;
          DOMAIN = "https://vaultwarden.${config.toh.meta.domains.service}";
        };
        services.vaultwarden.environmentFile = config.sops.secrets."vaultwarden-env".path;
        systemd.services.vaultwarden.wantedBy = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.requires = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.after = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        networking.firewall.allowedTCPPorts = [ port ];

        toh.meta.services = [
          {
            name = "vaultwarden";
            port = port;
            health = "http:///alive";
          }
        ];

        sops.secrets."vaultwarden-env" = {
          owner = vaultwardenUser;
          group = vaultwardenUser;
          mode = "0400";
        };
        sops.secrets."vaultwarden-auth-key" = {
          path = "${dataDir}/rsa_key.pem";
          owner = vaultwardenUser;
          group = vaultwardenUser;
          mode = "0400";
        };

        toh.cryl.machine.vaultwarden = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/vaultwarden-admin-pass";
                to = "vaultwarden-admin-pass";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/vaultwarden-auth-key";
                to = "vaultwarden-auth-key";
              };
            }
          ];
        };

        toh.cryl.cluster.vaultwarden = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/vaultwarden-admin-pass";
                to = "vaultwarden-admin-pass";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/vaultwarden-auth-key";
                to = "vaultwarden-auth-key";
                allow_fail = true;
              };
            }
          ];
          generations = [
            {
              generator = "script";
              arguments = {
                name = "vaultwarden-auth-key-script";
                text = ''
                  openssl genrsa -out vaultwarden-auth-key 4096
                '';
              };
            }
            {
              generator = "key";
              arguments = {
                name = "vaultwarden-admin-pass";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "vaultwarden-admin-pass";
                to = "${tohLib.secrets.directories.cluster}/vaultwarden-admin-pass";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "vaultwarden-auth-key";
                to = "${tohLib.secrets.directories.cluster}/vaultwarden-auth-key";
              };
            }
          ];
        };

        toh.meta.database.apps.vaultwarden = {
          user = config.systemd.services.vaultwarden.serviceConfig.User;
          group = config.systemd.services.vaultwarden.serviceConfig.User;
          init.nushell.file = pkgs.tohPackages.renderMustacheTemplate {
            name = "vaultwarden-init";
            templateFile = ./init.nu;
            variables = {
              TOH_VAULTWARDEN_INIT_ENV_PATH = config.sops.secrets."vaultwarden-env".path;
              TOH_VAULTWARDEN_INIT_DATA_DIR = dataDir;
              TOH_VAULTWARDEN_INIT_USER = vaultwardenUser;
              TOH_VAULTWARDEN_INIT_EXE = lib.getExe package;
              TOH_VAULTWARDEN_INIT_BASH = lib.getExe pkgs.bash;
            };
          };
          secrets.generations = [
            {
              generator = "mustache";
              arguments = {
                name = "vaultwarden-env";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DATABASE_VAULTWARDEN_URL = config.toh.meta.database.instances.vaultwarden.urlSecret;
                    ADMIN_TOKEN = "vaultwarden-admin-pass";
                  };
                };
                template = ''
                  DATABASE_URL="{{{DATABASE_VAULTWARDEN_URL}}}"
                  ADMIN_TOKEN="{{ADMIN_TOKEN}}"
                '';
              };
            }
          ];
        };
      };
    };
}
