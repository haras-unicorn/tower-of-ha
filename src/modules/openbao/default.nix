# TODO: HA SSL

{
  toh.lib.nixosModules.services-openbao =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.openbao;

      port = 8200;

      clusterPort = 8201;

      # NOTE: database instead of raft because it eliminates the need
      # for a bootstrap node
      database = config.toh.meta.database;
      instance = database.instances.openbao;

      variablesFormat = pkgs.formats.toml { };
      settingsFormat = pkgs.formats.json { };
      storageVariables =
        if database.protocol == "postgresql" then
          variablesFormat.generate "openbao-storage-variables" {
            DATABASE_OPENBAO_URL = "${instance.url}";
          }
        else
          throw "Unsupported database protocol ${database.protocol} for openbao";
      storageTemplate =
        if database.protocol == "postgresql" then
          settingsFormat.generate "openbao-storage-template" {
            storage.postgresql = {
              connection_url = "{{{DATABASE_OPENBAO_URL}}}";
              ha_enabled = true;
            };
          }
        else
          throw "Unsupported database protocol ${database.protocol} for openbao";
      runDirectory = "openbao";
      storageSettingsPath = "/run/${runDirectory}/storage.json";

      user = tohLib.openbao.user;
      group = tohLib.openbao.group;
    in
    {
      options.toh.services = {
        openbao = {
          enable = lib.mkEnableOption "openbao";
        };
      };

      config = lib.mkIf cfg.enable {
        services.openbao.enable = true;
        services.openbao.settings = {
          ui = true;
          api_addr = "http://${config.toh.meta.network.ip}:${builtins.toString port}";
          cluster_addr = "http://${config.toh.meta.network.ip}:${builtins.toString clusterPort}";
          listener.default = {
            type = "tcp";
            address = "${config.toh.meta.network.ip}:${builtins.toString port}";
            cluster_address = "${config.toh.meta.network.ip}:${builtins.toString clusterPort}";
            tls_disable = true;
          };
          seal."static" = {
            current_key_id = "openbao-unseal-key";
            current_key = "file://${config.toh.meta.sops.secrets."openbao-unseal-key".path}";
          };
        };
        services.openbao.extraArgs = [
          "-config"
          "${storageSettingsPath}"
        ];
        systemd.services.openbao = {
          wantedBy = [ "toh-database-online.target" ];
          requires = [ "toh-database-online.target" ];
          after = [ "toh-database-online.target" ];
          path = [ pkgs.tohPackages.mustacheRenderer ];
          preStart = lib.getExe (
            pkgs.tohPackages.writeNushellApplication {
              name = "openbao-render-storage-settings";
              text = ''
                (mustache-renderer
                  --variables "${storageVariables}"
                  --template "${storageTemplate}"
                  --out "${storageSettingsPath}"
                  --chmod 400
                  --chown "${user}:${group}")
              '';
            }
          );
          serviceConfig = {
            Restart = lib.mkForce "always";
            DynamicUser = lib.mkForce false;
            RuntimeDirectory = lib.mkForce runDirectory;
            User = user;
            Group = group;
          };
        };

        networking.firewall.allowedTCPPorts = [
          clusterPort
          port
        ];

        toh.meta.services.openbao = {
          endpoint.http = {
            inherit port;
          };
          health.endpoint.http = {
            inherit port;
            path = "v1/sys/health";
          };
        };

        # NOTE: for init we need one that forwards
        # even before initialization and unseal
        toh.meta.services.openbao-init = {
          endpoint.http = {
            inherit port;
          };
          health.endpoint.http = {
            inherit port;
            path = "v1/sys/health?activecode=200&standbycode=200&sealedcode=200&uninitcode=200";
          };
        };

        programs.rust-motd.settings = {
          service_status = {
            openbao = "openbao";
          };
        };

        toh.meta.sops.secrets."openbao-unseal-key" = {
          owner = user;
          group = group;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            openbao = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/openbao-unseal-key";
                    to = "openbao-unseal-key";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            openbao = {
              generations = [
                {
                  generator = "script";
                  arguments = {
                    name = "openbao-unseal-key";
                    text = "openssl rand -hex 32 | str trim | save -f openbao-unseal-key";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.database.apps.openbao = {
          inherit user group;
          init.sql.script =
            if database.protocol == "postgresql" then
              ''
                create table if not exists openbao_kv_store (
                  parent_path text not null,
                  path        text,
                  key         text,
                  value       bytea,
                  constraint openbao_kv_store_pkey primary key (path, key)
                );

                create index if not exists openbao_kv_store_idx on openbao_kv_store (parent_path);

                create table if not exists openbao_ha_locks (
                  ha_key                                      text not null,
                  ha_identity                                 text not null,
                  ha_value                                    text,
                  valid_until                                 timestamp with time zone not null,
                  constraint openbao_ha_locks_pkey primary key (ha_key)
                );
              ''
            else
              throw "Unsupported database protocol ${database.protocol} for openbao";
        };
      };
    };
}
