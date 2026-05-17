# TODO: HA SSL
# TODO: mysql

{
  toh.lib.nixosModules.services-vault =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.vault;

      port = 8200;

      clusterPort = 8201;

      database = config.toh.meta.database;
      instance = database.instances.vault;

      settingsPath = "/var/lib/${config.systemd.services.vault.serviceConfig.StateDirectory}/toh-settings.hcl";
      owner = config.systemd.services.vault.serviceConfig.User;
      group = config.systemd.services.vault.serviceConfig.User;
    in
    {
      options.toh.services = {
        vault = {
          enable = lib.mkEnableOption "Vault";
        };
      };

      config = lib.mkIf cfg.enable {
        services.vault.enable = true;
        services.vault.package = pkgs.vault-bin;
        services.vault.address = "${config.toh.meta.network.ip}:${builtins.toString port}";
        services.vault.storageBackend = config.toh.meta.database.protocol;
        services.vault.extraConfig = ''
          ui = true
          api_addr = "http://${config.toh.meta.network.ip}:${builtins.toString port}"
          cluster_addr = "http://${config.toh.meta.network.ip}:${builtins.toString clusterPort}"
        '';
        services.vault.extraSettingsPaths = [ settingsPath ];
        systemd.services.vault.serviceConfig.ExecStartPre = lib.mkMerge [
          (lib.mkIf (database.protocol == "postgresql") ''
            ${lib.getExe pkgs.tohPackages.mustacheRenderer} \
              --variables '{ "DATABASE_VAULT_URL": "${instance.url}" }' \
              --template 'storage "${database.protocol}" {
              connection_url = "{{{DATABASE_VAULT_URL}}}"
              ha_enabled = "true"
            }
            ' \
              --out "${settingsPath}" \
              --chmod 400 \
              --chown "${owner}:${group}"
          '')
          (lib.mkIf (database.protocol == "mysql") ''
            ${lib.getExe pkgs.tohPackages.mustacheRenderer} \
              --variables '{ "DATABASE_VAULT_PASSWORD": "${instance.password}" }' \
              --template 'storage "${database.protocol}" {
              address = "${database.host}:${builtins.toString database.port}"
              tls_ca = "${instance.parameters.ssl-capath}"
              username = "vault"
              password = "{{{DATABASE_VAULT_PASSWORD}}}"
              ha_enabled = "true"
            }
            ' \
              --out "${settingsPath}" \
              --chmod 400 \
              --chown "${owner}:${group}"
          '')
        ];

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

        toh.meta.services.vault = {
          endpoint.http.port = port;
          health.endpoint.http.path = "v1/sys/health?standbyok=true&perfstandbyok=true";
        };

        programs.rust-motd.settings = {
          service_status = {
            Vault = "vault";
          };
        };

        toh.meta.database.apps.vault = {
          user = config.systemd.services.vault.serviceConfig.User;
          group = config.systemd.services.vault.serviceConfig.User;
          init.sql.script = lib.mkIf (database.protocol == "postgresql") ''
            create table vault_kv_store (
              parent_path text collate "c" not null,
              path text collate "c",
              key text collate "c",
              value bytea,
              constraint pkey primary key (path, key)
            );

            create index parent_path_idx on vault_kv_store (parent_path);

            create table vault_ha_locks (
              ha_key text collate "c" not null,
              ha_identity text collate "c" not null,
              ha_value text collate "c",
              valid_until timestamp with time zone not null,
              constraint ha_key primary key (ha_key)
            );
          '';
        };
      };
    };
}
