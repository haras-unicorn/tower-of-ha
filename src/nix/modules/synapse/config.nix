{ selfLib, ... }:

{
  self.nixosModules.services-synapse-config.flake = true;
  self.nixosModules.services-synapse-config.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.synapse;

      dbConfig = config.toh.meta.database;
      dbInstance = config.toh.meta.database.instances.synapse;

      secrets = config.toh.meta.sops.secrets;

      owner = "matrix-synapse";
      group = "matrix-synapse";

      # NOTE: Synapse refuses a database that was not made with this locale
      databaseLocale = "C";

      databaseName =
        if dbConfig.protocol == "postgresql" then
          "psycopg2"
        else
          builtins.throw "Synapse database type not supported";

      script = pkgs.tohPackages.writeNushellApplication {
        name = "synapse-config";
        text = pkgs.harasPackages.renderMustacheText {
          name = "synapse-config-text";
          text = builtins.readFile ./config.nu;
          vars = {
            TOH_SYNAPSE_CONFIG = builtins.toJSON {
              inherit owner group;
              path = cfg.config.path;
              signingKeyPath = cfg.config.signingKeyPath;
              signingKeyVersion = cfg.config.signingKeyVersion;
              database = {
                name = databaseName;
                args = {
                  user = dbInstance.dbUser;
                  database = dbInstance.dbName;
                  host = dbConfig.host;
                  port = dbConfig.port;
                  sslmode = "verify-full";
                  sslrootcert = dbInstance.ssl.ca;
                  sslcert = dbInstance.ssl.crt;
                  sslkey = dbInstance.ssl.key;
                  connect_timeout = dbInstance.parameters.connect_timeout;
                };
              };
              passwordPath = dbInstance.password;
              registrationSecretPath = secrets."synapse-registration-shared-secret".path;
              macaroonSecretPath = secrets."synapse-macaroon-secret-key".path;
              replicationSecretPath = secrets."synapse-worker-replication-secret".path;
              signingSeedPath = secrets."synapse-signing-key-seed".path;
            };
          };
        };
      };
    in
    {
      options.toh.services.synapse = {
        config = {
          path = lib.mkOption {
            type = lib.types.path;
            default = "/run/secrets/synapse-config.yaml";
            description = ''
              Where the config with the secrets of Synapse is written when the
              main process starts.
            '';
          };

          signingKeyPath = lib.mkOption {
            type = lib.types.path;
            default = "/run/secrets/synapse-signing-key";
            description = "Where the signing key of the server is written.";
          };

          signingKeyVersion = lib.mkOption {
            type = lib.types.str;
            default = "toh";
            description = "The version in the signing key, which Synapse shows in signatures.";
          };
        };

        media.path = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/matrix-synapse/media_store";
          description = ''
            Where Synapse keeps uploaded media. It is a CephFS mount, because
            the main process moves between machines.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.synapse-config = {
          description = "Synapse config with secrets";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = lib.getExe script;
        };

        toh.meta.database.apps.synapse = {
          user = owner;
          group = group;
          dbLocale = databaseLocale;
        };

        # NOTE: the port is unique in the cluster, so it is also a database
        # of the key-value store that no other app uses, like Forgejo does
        toh.meta.kv.apps.synapse = {
          user = owner;
          group = group;
          database = cfg.port;
          prefix = "all";
          # NOTE: the workers talk to each other over channels named after
          # the server
          channels = config.toh.meta.chat.serverName;
          permissions = [
            selfLib.kv.permissions.read
            selfLib.kv.permissions.write
            selfLib.kv.permissions.keyspace
            selfLib.kv.permissions.connection
            selfLib.kv.permissions.pubsub
          ];
        };

        toh.meta.filesystem.mounts.${cfg.media.path} = {
          user = owner;
          group = group;
          mode = "0750";
        };

        toh.meta.sops.secrets = {
          "synapse-registration-shared-secret" = {
            inherit owner group;
            mode = "0400";
          };
          "synapse-macaroon-secret-key" = {
            inherit owner group;
            mode = "0400";
          };
          "synapse-worker-replication-secret" = {
            inherit owner group;
            mode = "0400";
          };
          "synapse-signing-key-seed" = {
            inherit owner group;
            mode = "0400";
          };
        };

        toh.meta.cryl.machine = [
          {
            synapse = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/synapse-registration-shared-secret";
                    to = "synapse-registration-shared-secret";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/synapse-macaroon-secret-key";
                    to = "synapse-macaroon-secret-key";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/synapse-worker-replication-secret";
                    to = "synapse-worker-replication-secret";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/synapse-signing-key-seed";
                    to = "synapse-signing-key-seed";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            synapse = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "synapse-registration-shared-secret";
                    length = 64;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "synapse-macaroon-secret-key";
                    length = 64;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "synapse-worker-replication-secret";
                    length = 64;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "synapse-signing-key-seed";
                    length = 64;
                  };
                }
              ];
            };
          }
        ];

        toh.pki.installCa = true;
      };
    };
}
