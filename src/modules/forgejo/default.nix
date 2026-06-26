{
  toh.lib.nixosModules.services-forgejo =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      anyMachines = tohLib.anyServiceMachines "forgejo";

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
      oidcClient = config.toh.meta.oidc.clients.forgejo;

      proxyHttpAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-http.endpoint;
      proxySshAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-ssh.endpoint;

      forgejoCfg = config.services.forgejo;

      owner = "forgejo";
      group = "forgejo";

      s3StorageSettings =
        basePath:
        {
          STORAGE_TYPE = "minio";
          SERVE_DIRECT = true;
          MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
          MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
          MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
          MINIO_BUCKET = "forgejo";
          MINIO_LOCATION = s3Config.region;
          MINIO_USE_SSL = true;
        }
        // lib.optionalAttrs (basePath != null) {
          MINIO_BASE_PATH = basePath;
        };
    in
    {
      options.toh.services = {
        forgejo = {
          enable = lib.mkEnableOption "Forgejo git service";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.git = {
            http = {
              host = proxyHttpAttrs.host;
              port = proxyHttpAttrs.port;
            };
            ssh = {
              host = proxySshAttrs.host;
              port = proxySshAttrs.port;
              user = owner;
            };
          };
        })
        (lib.mkIf cfg.enable {
          toh.overlays = tohLib.cli.makeOverlays {
            name = "forgejo-oauth";
            runtimeInputs = pkgs: [
              forgejoCfg.package
            ];
            textFile = ./oauth.nu;
            textVariables = {
              TOH_FORGEJO_OAUTH_BASE_URL = oidcConfg.baseUrl;
              TOH_FORGEJO_OAUTH_CLIENT_SECRET = oidcClient.clientSecret;
            };
          };

          environment.systemPackages = [
            pkgs.forgejo-cli
            pkgs.git
          ];

          services.forgejo = {
            enable = true;
            package = pkgs.forgejo-lts;
            user = owner;
            group = group;

            # NOTE: might seem weird but this just means
            # were the ones managing secrets and not nixpkgs
            useWizard = true;

            database = {
              createDatabase = false;
            };

            lfs.enable = true;

            repositoryRoot = "/var/lib/forgejo/repositories";

            settings = {
              server = {
                DOMAIN = proxyHttpAttrs.host;
                ROOT_URL = "https://${proxyHttpAttrs.host}/";
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

              repository = {
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
                PROTOCOL = "smtp";
                SMTP_ADDR = emailConfig.domain;
                SMTP_PORT = 25;
                FROM = emailInstance.address;
              };

              actions = {
                ENABLED = true;
              };

              openid = {
                ENABLE_OPENID_SIGNIN = true;
                WHITELISTED_URIS = oidcConfg.baseUrl;
              };

              attachment = s3StorageSettings null;
              lfs = s3StorageSettings "lfs/";
              avatar = s3StorageSettings null;
              "repo-avatar" = s3StorageSettings null;
              "repo-archive" = s3StorageSettings null;
              "storage.actions_log" = s3StorageSettings null;
              "actions.artifacts" = s3StorageSettings null;
            };
          };

          systemd.services.forgejo-secrets = {
            script = ''
              config="${forgejoCfg.customDir}/conf/app.ini"
              cat '${settingsFormat.generate "app.ini" forgejoCfg.settings}' > "$config"

              cat >> "$config" <<APPINIEOF
              [session]
              PROVIDER = redis
              PROVIDER_CONFIG = "$(cat "${kvSessionInstance.url}")"

              [cache]
              ADAPTER = redis
              HOST = "$(cat "${kvCacheInstance.url}")"

              [queue]
              TYPE = redis
              CONN_STR = $(cat "${kvQueueInstance.url}")
              APPINIEOF
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = owner;
              Group = group;
              ReadWritePaths = [ forgejoCfg.customDir ];
              UMask = "0077";
            };
          };

          systemd.services.forgejo = {
            wantedBy = [
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
              "toh-email-online.target"
              "toh-oidc-online.target"
            ];
            after = [
              "forgejo-secrets.service"
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
              "toh-email-online.target"
              "toh-oidc-online.target"
            ];
            requires = [
              "forgejo-secrets.service"
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
              "toh-email-online.target"
              "toh-oidc-online.target"
            ];
          };

          systemd.services.forgejo-oauth2 = {
            after = [ "forgejo.service" ];
            requires = [ "forgejo.service" ];
            path = [ pkgs.tohPackages.forgejo-oauth ];
            script = "forgejo-oauth";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = owner;
              Group = group;
              TimeoutStartSec = "infinity";
              Restart = "on-failure";
            };
          };

          systemd.targets.toh-git-online = {
            wantedBy = [
              "forgejo-secrets.service"
              "forgejo.service"
              "forgejo-oauth.service"
            ];
            bindsTo = [
              "forgejo-secrets.service"
              "forgejo.service"
              "forgejo-oauth.service"
            ];
            after = [
              "forgejo-secrets.service"
              "forgejo.service"
              "forgejo-oauth.service"
            ];
          };

          networking.firewall.allowedTCPPorts = [
            httpPort
            sshPort
          ];

          users.groups.${group} = { };
          users.users.${owner} = {
            home = forgejoCfg.stateDir;
            useDefaultShell = true;
            group = group;
            isSystemUser = true;
          };

          programs.rust-motd.settings.service_status.Forgejo = "forgejo";

          toh.meta.services.forgejo-http = {
            endpoint.http = {
              port = httpPort;
            };
            health.endpoint.http = {
              port = httpPort;
              path = "/api/healthz";
            };
          };

          toh.meta.services.forgejo-ssh = {
            endpoint.tcp = {
              port = sshPort;
              sslTermination = "passthrough";
            };
            health.endpoint.tcp = {
              port = sshPort;
              packets = [
                {
                  send = null;
                  expect = "SSH";
                }
              ];
            };
          };

          toh.meta.sops.secrets."forgejo-secret-key" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."forgejo-internal-token" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."forgejo-lfs-jwt-secret" = {
            inherit owner group;
            mode = "0400";
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

          toh.meta.filesystem.mounts."/var/lib/forgejo/repositories" = {
            user = owner;
            group = group;
            mode = "0750";
          };

          systemd.services.forgejo-db-migrate = {
            description = "Forgejo database migration";
            after = [ "forgejo-secrets.service" ];
            requires = [ "forgejo-secrets.service" ];
            path = [
              forgejoCfg.package
              pkgs.git
              pkgs.gnupg
            ];
            script = "forgejo migrate";
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
              "https://${proxyHttpAttrs.host}/user/oauth2/forgejo/callback"
            ];
          };

          toh.pki.installCa = true;
        })
      ];
    };
}
