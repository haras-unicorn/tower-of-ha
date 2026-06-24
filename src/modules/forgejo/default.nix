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

      proxyHttpAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-http.endpoint;
      proxySshAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-ssh.endpoint;

      forgejoCfg = config.services.forgejo;
      forgejoExe = lib.getExe forgejoCfg.package;

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
          environment.systemPackages = [
            pkgs.forgejo-cli
          ];

          services.forgejo = {
            enable = true;
            package = pkgs.forgejo-lts;
            user = owner;
            group = group;
            useWizard = false;

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

              database = {
                DB_TYPE = if dbConfig.protocol == "postgresql" then "postgres" else dbConfig.protocol;
                HOST = "${dbConfig.host}:${builtins.toString dbConfig.port}";
                NAME = dbInstance.dbName;
                USER = dbInstance.dbUser;
                SSL_MODE = "verify-full";
              };

              repository = {
                DEFAULT_BRANCH = "main";
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

              attachment = s3StorageSettings null;
              lfs = s3StorageSettings "lfs/";
              avatar = s3StorageSettings null;
              "repo-avatar" = s3StorageSettings null;
              "repo-archive" = s3StorageSettings null;
              "storage.actions_log" = s3StorageSettings null;
              "actions.artifacts" = s3StorageSettings null;
            };
          };

          systemd.services.forgejo-secrets.enable = lib.mkForce false;

          systemd.services.forgejo = {
            preStart = lib.mkForce ''
              config="${forgejoCfg.customDir}/conf/app.ini"
              cp -f '${pkgs.formats.ini { }.generate "app.ini" forgejoCfg.settings}' "$config"
              chmod u+w "$config"
              ${lib.getExe' forgejoCfg.package "environment-to-ini"} --config "$config"

              session_url="$(<"${kvSessionInstance.url}")"
              cache_url="$(<"${kvCacheInstance.url}")"
              queue_url="$(<"${kvQueueInstance.url}")"

              cat >> "$config" <<APPINIEOF

              [session]
              PROVIDER = redis
              PROVIDER_CONFIG = ''${session_url}

              [cache]
              ADAPTER = redis
              HOST = ''${cache_url}

              [queue]
              TYPE = redis
              CONN_STR = ''${queue_url}
              APPINIEOF

              chmod u-w "$config"

              ${forgejoExe} admin regenerate hooks

              if [ -r ${forgejoCfg.stateDir}/.ssh/authorized_keys ]; then
                ${forgejoExe} admin regenerate keys
              fi
            '';

            wantedBy = [
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
            ];
            after = [
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
              "forgejo-db-migrate.service"
            ];
            requires = [
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
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

          systemd.tmpfiles.rules = [
            "d /var/lib/forgejo 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/custom 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/custom/conf 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/data 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/log 0750 ${owner} ${group} -"
          ];

          programs.rust-motd.settings.service_status.Forgejo = "forgejo";

          toh.meta.services.forgejo-http = {
            endpoint.http = {
              port = httpPort;
            };
            health.endpoint.http = {
              inherit httpPort;
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
            path = "${forgejoCfg.customDir}/conf/secret_key";
          };

          toh.meta.sops.secrets."forgejo-internal-token" = {
            inherit owner group;
            mode = "0400";
            path = "${forgejoCfg.customDir}/conf/internal_token";
          };

          toh.meta.sops.secrets."forgejo-jwt-secret" = {
            inherit owner group;
            mode = "0400";
            path = "${forgejoCfg.customDir}/conf/oauth2_jwt_secret";
          };

          toh.meta.sops.secrets."forgejo-lfs-jwt-secret" = {
            inherit owner group;
            mode = "0400";
            path = "${forgejoCfg.customDir}/conf/lfs_jwt_secret";
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
            path = [
              forgejoCfg.package
              pkgs.git
              pkgs.gnupg
            ];
            script = ''
              session_url="$(<"${kvSessionInstance.url}")"
              cache_url="$(<"${kvCacheInstance.url}")"
              queue_url="$(<"${kvQueueInstance.url}")"

              config="${forgejoCfg.customDir}/conf/app.ini"
              cp -f '${pkgs.formats.ini { }.generate "app.ini" forgejoCfg.settings}' "$config"
              chmod u+w "$config"
              ${lib.getExe' forgejoCfg.package "environment-to-ini"} --config "$config"

              cat >> "$config" <<APPINIEOF

              [session]
              PROVIDER = redis
              PROVIDER_CONFIG = ''${session_url}

              [cache]
              ADAPTER = redis
              HOST = ''${cache_url}

              [queue]
              TYPE = redis
              CONN_STR = ''${queue_url}
              APPINIEOF

              chmod u-w "$config"

              ${forgejoExe} migrate
            '';
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
            permissions = [ tohLib.kv.permissions.all ];
          };

          toh.meta.kv.apps.forgejo-cache = {
            user = owner;
            group = group;
            database = httpPort + 1;
            prefix = "all";
            permissions = [ tohLib.kv.permissions.all ];
          };

          toh.meta.kv.apps.forgejo-queue = {
            user = owner;
            group = group;
            database = httpPort + 2;
            prefix = "all";
            permissions = [ tohLib.kv.permissions.all ];
          };

          toh.meta.email.apps.forgejo = {
            user = owner;
            group = group;
          };

          toh.meta.oidc.apps.forgejo = {
            user = owner;
            group = group;
            redirectUris = [
              "https://${proxyHttpAttrs.host}/user/oauth2/authelia/callback"
              "https://${proxyHttpAttrs.host}/user/oauth2/forgejo/callback"
            ];
          };

          toh.pki.installCa = true;
        })
      ];
    };
}
