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

      dbConfig = config.toh.meta.database;
      dbInstance = config.toh.meta.database.instances.forgejo;

      s3Config = config.toh.meta.s3;
      s3BucketConfig = config.toh.meta.s3.buckets.forgejo;

      kvConfig = config.toh.meta.kv;
      kvInstance = config.toh.meta.kv.instances.forgejo;

      emailConfig = config.toh.meta.email;

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-http.endpoint;

      owner = "forgejo";
      group = "forgejo";
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
            host = proxyAttrs.host;
            httpPort = proxyAttrs.port;
            url = "https://${proxyAttrs.host}";
          };
        })
        (lib.mkIf cfg.enable {
          environment.systemPackages = [
            pkgs.tohPackages.cli
            pkgs.forgejo-cli
          ];

          services.forgejo = {
            enable = true;
            package = pkgs.forgejo-lts;
            user = owner;
            group = group;
            useWizard = false;

            database = {
              type = "postgres";
              host = dbConfig.host;
              port = dbConfig.port;
              name = "forgejo";
              user = "forgejo";
              createDatabase = false;
              passwordFile = lib.mkDefault dbInstance.password;
            };

            lfs.enable = true;

            repositoryRoot = "/var/lib/forgejo/repositories";

            settings = {
              DEFAULT = {
                RUN_MODE = "prod";
                APP_NAME = "ToH Git";
              };

              server = {
                DOMAIN = proxyAttrs.host;
                ROOT_URL = "https://${proxyAttrs.host}/";
                HTTP_ADDR = config.toh.meta.network.ip;
                HTTP_PORT = httpPort;
                PROTOCOL = "http";
                DISABLE_SSH = true;
                OFFLINE_MODE = true;
                LFS_START_SERVER = true;
                LANDING_PAGE = "explore";
                STATIC_CACHE_TIME = "24h";
              };

              database = {
                SSL_MODE = lib.mkForce "verify-full";
              };

              repository = {
                ENABLE_PUSH_CREATE_USER = true;
                ENABLE_PUSH_CREATE_ORG = true;
                PREFERRED_LICENSES = "Apache-2.0,MIT,AGPL-3.0,GPL-3.0";
                DEFAULT_BRANCH = "main";
              };

              "repository.signing" = {
                INITIAL_COMMIT = "always";
                DEFAULT_TRUST_MODEL = "committer";
                CRUD_ACTIONS = "pubkey,twofa,parentsigned";
                MERGES = "pubkey,twofa,basesigned,commitssigned";
              };

              service = {
                DISABLE_REGISTRATION = true;
                ENABLE_NOTIFY_MAIL = true;
                DEFAULT_KEEP_EMAIL_PRIVATE = true;
                REQUIRE_SIGNIN_VIEW = false;
              };

              mailer = {
                ENABLED = true;
                PROTOCOL = "sendmail";
                FROM = "forgejo@${emailConfig.domain}";
              };

              packages = {
                ENABLED = true;
              };

              actions = {
                ENABLED = true;
              };

              federation = {
                ENABLED = false;
              };

              other = {
                SHOW_FOOTER_VERSION = false;
              };

              attachment = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };

              lfs = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
                MINIO_BASE_PATH = "lfs/";
              };

              avatar = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };

              "repo-avatar" = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };

              "repo-archive" = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };

              "storage.actions_log" = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };

              "actions.artifacts" = {
                STORAGE_TYPE = "minio";
                SERVE_DIRECT = true;
                MINIO_ENDPOINT = "${s3Config.host}:${builtins.toString s3Config.port}";
                MINIO_ACCESS_KEY_ID_FILE = s3BucketConfig.keyId;
                MINIO_SECRET_ACCESS_KEY_FILE = s3BucketConfig.secretKey;
                MINIO_BUCKET = "forgejo";
                MINIO_LOCATION = s3Config.region;
                MINIO_USE_SSL = true;
              };
            };
          };

          toh.meta.filesystem.mounts."/var/lib/forgejo/repositories" = {
            directory = "forgejo/repositories";
            user = owner;
            group = group;
            mode = "0750";
          };

          networking.firewall.allowedTCPPorts = [ httpPort ];

          users.groups.${group} = { };
          users.users.${owner} = {
            group = group;
            isSystemUser = true;
            home = "/var/lib/forgejo";
          };

          systemd.tmpfiles.rules = [
            "d /var/lib/forgejo 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/custom 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/custom/conf 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/data 0750 ${owner} ${group} -"
            "d /var/lib/forgejo/log 0750 ${owner} ${group} -"
          ];

          systemd.services.forgejo-secrets = lib.mkForce {
            description = "Forgejo secret bootstrap (managed by cryl)";
            script = "true";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = owner;
              Group = group;
            };
          };

          systemd.services.forgejo = {
            preStart = lib.mkAfter ''
              url_file="${kvInstance.url}"
              redis_url="$(<"$url_file")"
              redis_rest="''${redis_url#*://}"
              redis_pass="''${redis_rest#*:}"
              redis_pass="''${redis_pass%%@*}"
              redis_hostport="''${redis_rest#*@}"
              redis_hostport="''${redis_hostport%%\?*}"

              config="${config.services.forgejo.customDir}/conf/app.ini"
              chmod u+w "$config"

              cat >> "$config" <<APPINIEOF

              [session]
              PROVIDER = redis
              PROVIDER_CONFIG = rediss://:''${redis_pass}@''${redis_hostport}/0?pool_size=100&idle_timeout=180s

              [cache]
              ADAPTER = redis
              HOST = rediss://:''${redis_pass}@''${redis_hostport}/1?pool_size=100&idle_timeout=180s

              [queue]
              TYPE = redis
              CONN_STR = rediss://:''${redis_pass}@''${redis_hostport}/2
              APPINIEOF

              chmod u-w "$config"
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
            ];
            requires = [
              "toh-database-online.target"
              "toh-s3-online.target"
              "toh-kv-online.target"
              "toh-filesystem-online.target"
            ];
          };

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

          toh.meta.sops.secrets."forgejo-secret-key" = {
            inherit owner group;
            mode = "0400";
            path = "${config.services.forgejo.customDir}/conf/secret_key";
          };

          toh.meta.sops.secrets."forgejo-internal-token" = {
            inherit owner group;
            mode = "0400";
            path = "${config.services.forgejo.customDir}/conf/internal_token";
          };

          toh.meta.sops.secrets."forgejo-jwt-secret" = {
            inherit owner group;
            mode = "0400";
            path = "${config.services.forgejo.customDir}/conf/oauth2_jwt_secret";
          };

          toh.meta.sops.secrets."forgejo-lfs-jwt-secret" = {
            inherit owner group;
            mode = "0400";
            path = "${config.services.forgejo.customDir}/conf/lfs_jwt_secret";
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

          toh.meta.database.apps.forgejo = {
            user = owner;
            group = group;
          };

          toh.meta.s3.apps.forgejo = {
            user = owner;
            group = group;
          };

          toh.meta.kv.apps.forgejo = {
            user = owner;
            group = group;
            database = httpPort;
            prefix = "forgejo:";
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
              "https://${proxyAttrs.host}/user/oauth2/authelia/callback"
              "https://${proxyAttrs.host}/user/oauth2/forgejo/callback"
            ];
          };

          toh.pki.installCa = true;

          toh.services.forgejo.runner.enable = lib.mkDefault true;
        })
      ];

      imports = [
        ./runner.nix
      ];
    };
}
