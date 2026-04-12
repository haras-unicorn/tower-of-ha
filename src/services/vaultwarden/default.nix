{ self, ... }:

{
  flake.nixosModules.services-vaultwarden =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      hosts = builtins.filter (
        host:
        if lib.hasAttrByPath [ "system" "toh" "vaultwarden" "enable" ] host then
          host.system.toh.vaultwarden.enable
        else
          false
      ) config.toh.host.hosts;

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
      options.toh = {
        vaultwarden = {
          enable = lib.mkEnableOption "Vaultwarden";
        };
      };

      config = lib.mkIf config.toh.vaultwarden.enable {
        services.vaultwarden.enable = true;
        services.vaultwarden.package = package;
        # TODO: remove mention of postgres here
        services.vaultwarden.dbBackend = "postgresql";
        services.vaultwarden.config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = port;
          SIGNUPS_ALLOWED = true;
          ENABLE_WEBSOCKET = false;
          DOMAIN = "https://vaultwarden.${config.toh.domains.service}";
        };
        services.vaultwarden.environmentFile = config.sops.secrets."vaultwarden-env".path;
        systemd.services.vaultwarden.wantedBy = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.requires = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.after = [ "toh-database-initialized.target" ];
        systemd.services.vaultwarden.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        networking.firewall.allowedTCPPorts = [ port ];

        toh.services = [
          {
            name = "vaultwarden";
            port = port;
            health = "http:///alive";
          }
        ];

        sops.secrets."vaultwarden-env" = {
          owner = config.systemd.services.vaultwarden.serviceConfig.User;
          group = config.systemd.services.vaultwarden.serviceConfig.User;
          mode = "0400";
        };
        sops.secrets."vaultwarden-auth-key" = {
          path = "${dataDir}/rsa_key.pem";
          owner = config.systemd.services.vaultwarden.serviceConfig.User;
          group = config.systemd.services.vaultwarden.serviceConfig.User;
          mode = "0400";
        };

        toh.cryl.host.vaultwarden = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/vaultwarden-admin-pass";
                to = "vaultwarden-admin-pass";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/vaultwarden-auth-key";
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
                from = "${self.lib.cryl.directories.cluster}/vaultwarden-admin-pass";
                to = "vaultwarden-admin-pass";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/vaultwarden-auth-key";
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
                to = "${self.lib.cryl.directories.cluster}/vaultwarden-admin-pass";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "vaultwarden-auth-key";
                to = "${self.lib.cryl.directories.cluster}/vaultwarden-auth-key";
              };
            }
          ];
        };

        toh.database.apps.vaultwarden = {
          hosts = builtins.map ({ name, ... }: name) hosts;
          user = config.systemd.services.vaultwarden.serviceConfig.User;
          group = config.systemd.services.vaultwarden.serviceConfig.User;
          init.bash.script = ''
            echo "Running vaultwarden migrations..."
            export DATABASE_URL="$(grep DATABASE_URL ${
              config.sops.secrets."vaultwarden-env".path
            } | cut -d'"' -f2)"
            export ADMIN_TOKEN="temp"
            export ROCKET_ADDRESS="127.0.0.1"
            export ROCKET_PORT="18222"
            export SIGNUPS_ALLOWED="true"
            export ENABLE_WEBSOCKET="false"
            export DATA_FOLDER="${dataDir}"
            export WEB_VAULT_ENABLED="false"
            export EXTENDED_LOGGING="true"
            export LOG_LEVEL="info"

            mkdir -p "$DATA_FOLDER"
            chown "${vaultwardenUser}:${vaultwardenUser}" "$DATA_FOLDER"

            log_file=$(mktemp)
            trap 'rm -f "$log_file"' EXIT

            runuser -u "${vaultwardenUser}" -- "${lib.getExe package}" > "$log_file" 2>&1 &
            vaultwarden_pid=$!
            migrations_done=false

            while IFS= read -r line; do
                echo "vaultwarden: $line"
                if echo "$line" | grep -q "Rocket has launched"; then
                    echo "Vaultwarden server launched"
                    migrations_done=true
                    kill $vaultwarden_pid 2>/dev/null
                    break
                fi
            done < <(tail -n +1 -f "$log_file")
            wait $vaultwarden_pid

            if [ "$migrations_done" != "true" ]; then
                echo "Vaultwarden failed before migrations completed"
                exit 1
            fi

            echo "Vaultwarden migrations completed successfully"
          '';
          secrets.generations = [
            {
              generator = "mustache";
              arguments = {
                name = "vaultwarden-env";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DATABASE_VAULTWARDEN_URL = config.toh.database.instances.vaultwarden.urlSecret;
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
