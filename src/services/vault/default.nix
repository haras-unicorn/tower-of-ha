# TODO: HA SSL

{
  flake.nixosModules.services-vault =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      hosts = builtins.filter (
        host:
        if lib.hasAttrByPath [ "system" "toh" "vault" "enable" ] host then
          host.system.toh.vault.enable
        else
          false
      ) config.toh.host.hosts;

      port = 8200;

      clusterPort = 8201;
    in
    {
      options.toh = {
        vault = {
          enable = lib.mkEnableOption "Vault";
        };
      };

      config = lib.mkIf config.toh.vault.enable {
        services.vault.enable = true;
        services.vault.package = pkgs.vault-bin;
        services.vault.address = "0.0.0.0:${builtins.toString port}";
        # TODO: remove mentions of cockroachdb and postgres here
        # NOTE: nixpkgs requires something here but i put cockroachdb at the bottom
        services.vault.storageBackend = "postgresql";
        services.vault.extraConfig = ''
          ui = true
          api_addr = "http://${config.toh.host.ip}:${builtins.toString port}"
          cluster_addr = "http://${config.toh.host.ip}:${builtins.toString clusterPort}"
        '';
        services.vault.extraSettingsPaths = [ config.sops.secrets."vault-settings".path ];

        networking.firewall.allowedTCPPorts = [
          clusterPort
          port
        ];

        systemd.services.vault.wantedBy = [ "toh-database-initialized.target" ];
        systemd.services.vault.requires = [ "toh-database-initialized.target" ];
        systemd.services.vault.after = [ "toh-database-initialized.target" ];
        systemd.services.vault.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        toh.services = [
          {
            name = "vault";
            port = port;
            health = "http:///v1/sys/health?standbyok=true&perfstandbyok=true";
          }
        ];

        programs.rust-motd.settings = {
          service_status = {
            Vault = "vault";
          };
        };

        sops.secrets."vault-settings" = {
          owner = config.systemd.services.vault.serviceConfig.User;
          group = config.systemd.services.vault.serviceConfig.User;
          mode = "0400";
        };

        toh.database.apps.vault = {
          hosts = builtins.map ({ name, ... }: name) hosts;
          user = config.systemd.services.vault.serviceConfig.User;
          group = config.systemd.services.vault.serviceConfig.User;
          init.sql.script = ''
            create table if not exists vault_kv_store (
              path string not null,
              value bytes null,
              constraint vault_kv_store_pkey primary key (path asc)
            );

            create table if not exists vault_ha_locks (
              ha_key string not null,
              ha_identity string not null,
              ha_value string null,
              valid_until timestamptz not null,
              constraint ha_key primary key (ha_key asc)
            );
          '';
          secrets.generations = [
            {
              generator = "mustache";
              arguments = {
                name = "vault-settings";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DATABASE_VAULT_URL = config.toh.database.instances.vault.urlSecret;
                  };
                };
                # TODO: remove mention of cockroachdb here
                template = ''
                  storage "cockroachdb" {
                    connection_url = "{{{DATABASE_VAULT_URL}}}"
                    ha_enabled = "true"
                  }
                '';
              };
            }
          ];
        };
      };
    };
}
