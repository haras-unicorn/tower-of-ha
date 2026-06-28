{
  toh.lib.nixosModules.services-forgejo-config =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      settingsFormat = pkgs.formats.ini { };

      httpPort = 3000;
      sshPort = 2222;

      dbConfig = config.toh.meta.database;
      dbInstance = config.toh.meta.database.instances.forgejo;

      s3Config = config.toh.meta.s3;
      s3BucketConfig = config.toh.meta.s3.buckets.forgejo;

      kvSessionInstance = config.toh.meta.kv.instances.forgejo-session;
      kvCacheInstance = config.toh.meta.kv.instances.forgejo-cache;
      kvQueueInstance = config.toh.meta.kv.instances.forgejo-queue;

      emailConfig = config.toh.meta.email;
      emailInstance = config.toh.meta.email.emails.forgejo;

      oidcConfg = config.toh.meta.oidc;

      makeHttpProxyUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.forgejo.endpoint;
      proxyHttpAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo.endpoint;

      forgejoCfg = config.services.forgejo;
      configFile = cfg.config.path;
      forgejoSettings = settingsFormat.generate "forgejo-config" (
        builtins.removeAttrs forgejoCfg.settings [ "database" ]
      );
      forgejoDbType =
        if dbConfig.protocol == "postgresql" then
          "postgres"
        else if dbConfig.protocol == "mysql" then
          "mysql"
        else if dbConfig.protocol == "sqlite" then
          "sqlite3"
        else
          builtins.throw "Forgejo database type not supported";

      owner = "forgejo";
      group = "forgejo-config";

      serviceTargets = [
        "toh-database-online.target"
        "toh-s3-online.target"
        "toh-kv-online.target"
        "toh-filesystem-online.target"
        "toh-email-online.target"
        "toh-oidc-online.target"
      ];
      serviceDependencies = [
        "forgejo-config.service"
      ]
      ++ serviceTargets;
    in
    {
      options.toh.services = {
        forgejo = {
          config = {
            enable = lib.mkEnableOption "Enable forgejo config generation" // {
              default = cfg.enable || cfg.runner.enable || cfg.init.enable;
            };

            path = lib.mkOption {
              type = lib.types.path;
              default = "/run/secrets/forgejo-config";
              description = "Forgejo config location";
            };
          };
        };
      };

      config = lib.mkIf cfg.config.enable {
        services.forgejo = {
          database.createDatabase = false;
          lfs.enable = true;
          repositoryRoot = "/var/lib/forgejo/repositories";
          settings = {
            DEFAULT = {
              RUN_MODE = "prod";
              RUN_USER = forgejoCfg.user;
              WORK_PATH = forgejoCfg.stateDir;
            };

            server = {
              DOMAIN = proxyHttpAttrs.host;
              ROOT_URL = makeHttpProxyUrl { };
              HTTP_ADDR = config.toh.meta.network.ip;
              HTTP_PORT = httpPort;
              PROTOCOL = "http";
              OFFLINE_MODE = true;
              LFS_START_SERVER = true;
              SSH_PORT = sshPort;
              START_SSH_SERVER = true;
              SSH_LISTEN_PORT = sshPort;
              SSH_LISTEN_HOST = config.toh.meta.network.ip;
              BUILTIN_SSH_SERVER_USER = owner;
            };

            service = {
              DISABLE_REGISTRATION = true;
            };

            security = {
              INSTALL_LOCK = true;
            };

            log = {
              LEVEL = "Warn";
            };

            actions = {
              ENABLED = true;
            };

            lfs = {
              PATH = forgejoCfg.lfs.contentDir;
            };

            repository = {
              ROOT = forgejoCfg.repositoryRoot;
              DEFAULT_BRANCH = "main";
            };

            database = {
              DB_TYPE = lib.mkForce (
                if dbConfig.protocol == "postgresql" then
                  "postgres"
                else if dbConfig.protocol == "mysql" then
                  "mysql"
                else if dbConfig.protocol == "sqlite" then
                  "sqlite3"
                else
                  builtins.throw "Forgejo database type not supported"
              );
              HOST = "${dbConfig.host}:${builtins.toString dbConfig.port}";
              NAME = dbInstance.dbName;
              USER = dbInstance.dbUser;
              SSL_MODE = "verify-full";
              AUTO_MIGRATION = false;
            };

            mailer = {
              ENABLED = true;
              PROTOCOL = "smtps";
              SMTP_ADDR = emailConfig.domain;
              SMTP_PORT = 25;
              FROM = emailInstance.address;
            };

            openid = {
              ENABLE_OPENID_SIGNIN = true;
              WHITELISTED_URIS = oidcConfg.baseUrl;
            };

            storage = {
              STORAGE_TYPE = "minio";
              MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
              MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
              MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
              MINIO_BUCKET = "forgejo";
              MINIO_LOCATION = s3Config.region;
              MINIO_USE_SSL = true;
            };

            session = {
              COOKIE_NAME = "forgejo-session";
            };
          };
        };

        systemd.services.forgejo-config = {
          script = ''
            cat "${forgejoSettings}" > "${configFile}"
            cat >> "${configFile}" <<EOF
            [session]
            PROVIDER = redis
            PROVIDER_CONFIG = "$(cat "${kvSessionInstance.url}")"

            [cache]
            ADAPTER = redis
            HOST = "$(cat "${kvCacheInstance.url}")"

            [queue]
            TYPE = redis
            CONN_STR = $(cat "${kvQueueInstance.url}")

            [database]
            DB_TYPE = ${forgejoDbType}
            HOST = ${dbConfig.host}:${builtins.toString dbConfig.port}
            NAME = ${dbInstance.dbName}
            USER = ${dbInstance.dbUser}
            SSL_MODE = verify-full
            AUTO_MIGRATION = false
            PASSWD = "$(cat ${dbInstance.password})"

            [storage]
            STORAGE_TYPE = minio
            MINIO_ENDPOINT = ${s3Config.host}:${builtins.toString s3Config.port}
            MINIO_ACCESS_KEY_ID = "$(cat ${s3BucketConfig.keyId})"
            MINIO_SECRET_ACCESS_KEY = "$(cat ${s3BucketConfig.secretKey})"
            MINIO_BUCKET = forgejo
            MINIO_LOCATION = "${s3Config.region}"
            MINIO_USE_SSL = true
            EOF
            chmod 640 "${configFile}"
            chown "${owner}:${group}" "${configFile}"
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        systemd.services.forgejo = {
          wantedBy = serviceTargets;
          after = serviceDependencies;
          requires = serviceDependencies;
        };

        systemd.services.forgejo-runner = {
          wantedBy = serviceTargets;
          after = serviceDependencies;
          requires = serviceDependencies;
        };

        systemd.services.forgejo-runner-config = {
          wantedBy = serviceTargets;
          after = serviceDependencies;
          requires = serviceDependencies;
        };

        systemd.services.forgejo-init = {
          wantedBy = serviceTargets;
          after = serviceDependencies;
          requires = serviceDependencies;
        };

        systemd.targets.toh-git-online = {
          wantedBy = [
            "forgejo-config.service"
          ];
          bindsTo = [
            "forgejo-config.service"
          ];
          after = [
            "forgejo-config.service"
          ];
        };

        toh.meta.sops.secrets = {
          "forgejo-secret-key" = {
            inherit owner group;
            mode = "0440";
          };
          "forgejo-internal-token" = {
            inherit owner group;
            mode = "0440";
          };
          "forgejo-lfs-jwt-secret" = {
            inherit owner group;
            mode = "0440";
          };
        };

        toh.meta.cryl.machine = [
          {
            forgejo = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-secret-key";
                    to = "forgejo-secret-key";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-internal-token";
                    to = "forgejo-internal-token";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-jwt-secret";
                    to = "forgejo-jwt-secret";
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-lfs-jwt-secret";
                    to = "forgejo-lfs-jwt-secret";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            forgejo = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "forgejo-secret-key";
                    length = 64;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "forgejo-internal-token";
                    length = 64;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "forgejo-jwt-secret";
                    length = 43;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "forgejo-lfs-jwt-secret";
                    length = 43;
                  };
                }
              ];
            };
          }
        ];

        toh.meta.filesystem.mounts."/var/lib/forgejo/repositories" = lib.mkIf cfg.enable {
          user = owner;
          group = group;
          mode = "0750";
        };

        systemd.services.forgejo-db-migrate = {
          description = "Forgejo database migration";
          after = [ "forgejo-config.service" ];
          requires = [ "forgejo-config.service" ];
          path = [ forgejoCfg.package ];
          script = ''forgejo migrate --config "${configFile}"'';
          serviceConfig = {
            User = owner;
            Group = group;
            Type = "oneshot";
          };
        };

        toh.meta.database.apps.forgejo = {
          user = owner;
          group = group;
          dbName = "forgejo";
          dbUser = "forgejo";
          init.systemd.unit = "forgejo-db-migrate.service";
          init.sql.script = ''
            CREATE TABLE IF NOT EXISTS __toh_action_runners (
              name TEXT PRIMARY KEY,
              uuid TEXT NOT NULL
            );
          '';
        };

        toh.meta.s3.apps.forgejo = {
          user = owner;
          group = group;
        };

        toh.meta.kv.apps.forgejo-session = {
          user = owner;
          group = group;
          database = httpPort;
          prefix = "all";
          permissions = [
            tohLib.kv.permissions.read
            tohLib.kv.permissions.write
            tohLib.kv.permissions.connection
            tohLib.kv.permissions.keyspace
          ];
        };

        toh.meta.kv.apps.forgejo-cache = {
          user = owner;
          group = group;
          database = httpPort + 1;
          prefix = "all";
          permissions = [
            tohLib.kv.permissions.read
            tohLib.kv.permissions.write
            tohLib.kv.permissions.connection
            tohLib.kv.permissions.keyspace
          ];
        };

        toh.meta.kv.apps.forgejo-queue = {
          user = owner;
          group = group;
          database = httpPort + 2;
          prefix = "all";
          permissions = [
            tohLib.kv.permissions.read
            tohLib.kv.permissions.write
            tohLib.kv.permissions.connection
            tohLib.kv.permissions.keyspace
          ];
        };

        toh.meta.email.apps.forgejo = {
          user = owner;
          group = group;
        };

        toh.meta.oidc.apps.forgejo = {
          user = owner;
          group = group;
          pkce = true;
          redirectUris = [
            (makeHttpProxyUrl { path = "user/oauth2/forgejo/callback"; })
          ];
        };

        toh.pki.installCa = true;

        toh.services.forgejo.createGroup = true;
      };
    };
}
