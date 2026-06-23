# NOTE: this service is incomplete and requires to be tested thoroughly!!!
# please do not take into account anything in this service file or its test file

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

      package = pkgs."vaultwarden-${config.toh.meta.database.protocol}";

      dataDir = "/var/lib/${config.systemd.services.vaultwarden.serviceConfig.StateDirectory}";

      vaultwardenUser = config.systemd.services.vaultwarden.serviceConfig.User;

      envFilePath = "${dataDir}/toh.env";
      owner = config.systemd.services.vaultwarden.serviceConfig.User;
      group = config.systemd.services.vaultwarden.serviceConfig.Group;
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
        services.vaultwarden.dbBackend = config.toh.meta.database.protocol;
        services.vaultwarden.config = {
          ROCKET_ADDRESS = config.toh.meta.network.ip;
          ROCKET_PORT = port;
          SIGNUPS_ALLOWED = true;
          ENABLE_WEBSOCKET = false;
          DOMAIN = "https://vaultwarden.${config.toh.meta.domains.service}";
        };
        systemd.services.vaultwarden.wantedBy = [ "toh-database-online.target" ];
        systemd.services.vaultwarden.requires = [ "toh-database-online.target" ];
        systemd.services.vaultwarden.after = [ "toh-database-online.target" ];
        services.vaultwarden.environmentFile = envFilePath;
        systemd.services.vaultwarden.serviceConfig = {
          Restart = lib.mkForce "always";
          ExecStartPre = ''
            ${lib.getExe pkgs.tohPackages.mustacheRenderer} \
              --variables '{
                  "DATABASE_VAULTWARDEN_URL": "${config.toh.meta.database.instances.vaultwarden.url}",
                  "ADMIN_TOKEN": "${config.toh.meta.sops.secrets."vaultwarden-admin-pass".path}"
                }' \
              --template 'DATABASE_URL="{{{DATABASE_VAULTWARDEN_URL}}}"
            ADMIN_TOKEN="{{ADMIN_TOKEN}}"
            ' \
              --out "${envFilePath}" \
              --chmod 400 \
              --chown "${owner}:${group}"
          '';
        };

        networking.firewall.allowedTCPPorts = [ port ];

        toh.meta.services.vaultwarden = {
          endpoint.http.port = port;
          health.endpoint.http.path = "alive";
        };

        toh.meta.sops.secrets."vaultwarden-admin-pass" = {
          inherit owner group;
          mode = "0400";
        };
        toh.meta.sops.secrets."vaultwarden-auth-key" = {
          inherit owner group;
          path = "${dataDir}/rsa_key.pem";
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            vaultwarden = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/vaultwarden-admin-pass";
                    to = "vaultwarden-admin-pass";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/vaultwarden-auth-key";
                    to = "vaultwarden-auth-key";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            vaultwarden = {
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
            };
          }
        ];

        toh.meta.database.apps.vaultwarden = {
          user = owner;
          group = group;
          init.nushell.file = pkgs.tohPackages.renderMustacheTemplate {
            name = "vaultwarden-init";
            templateFile = ./init.nu;
            variables = {
              TOH_VAULTWARDEN_INIT_ENV_PATH = config.toh.meta.sops.secrets."vaultwarden-env".path;
              TOH_VAULTWARDEN_INIT_DATA_DIR = dataDir;
              TOH_VAULTWARDEN_INIT_USER = vaultwardenUser;
              TOH_VAULTWARDEN_INIT_EXE = lib.getExe package;
              TOH_VAULTWARDEN_INIT_BASH = lib.getExe pkgs.bash;
            };
          };
        };
      };
    };
}
