{
  toh.lib.nixosModules.services-patroni-users =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      osUsers = config.users.users;

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.postgresql.endpoint;

      mergeByUser =
        forEachUser:
        lib.mkMerge (
          builtins.map (
            { name, value }:
            forEachUser (
              value
              // (rec {
                user = name;

                isSuperuser = builtins.elem name (builtins.attrValues tohLib.patroni.superusers);

                isCliUser = !isSuperuser || name == tohLib.patroni.superusers.superuser;

                owner = if isSuperuser then config.services.patroni.user else value.user;
                group = if isSuperuser then config.services.patroni.group else value.group;
              })
            )
          ) (lib.attrsToList config.toh.services.patroni.users)
        );
    in
    {
      options.toh.services = {
        patroni = {
          users = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, config, ... }:
                let
                  certs =
                    if
                      builtins.elem name (builtins.attrValues tohLib.patroni.superusers)
                      || !builtins.elem name (builtins.attrNames osUsers)
                      || osUsers.${name}.home == "/var/empty"
                    then
                      "${tohLib.patroni.certs.root}/${name}"
                    else
                      builtins.replaceStrings [ "~" ] [ osUsers.${name}.home ] tohLib.patroni.certs.user;
                in
                {
                  options = {
                    installSecrets = lib.mkEnableOption "patroni user secrets installation";

                    generateSecrets = lib.mkEnableOption "patroni user secrets generation";

                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "User owner of secrets";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Group owner of secrets";
                    };
                    password = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.password}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.password}"'';
                      description = "Path to user Patroni environment file";
                    };
                    env = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.env}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.env}"'';
                      description = "Path to user Patroni environment file";
                    };
                    url = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.url}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.url}"'';
                      description = "Path to user Patroni URL file";
                    };
                    ca = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.certs.ca}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.certs.ca}"'';
                      description = "Path to user Patroni root certificate";
                    };
                    crt = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.certs.crt}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.certs.crt}"'';
                      description = "Path to user Patroni certificate";
                    };
                    key = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.patroni.certs.key}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.patroni.certs.key}"'';
                      description = "Path to user Patroni key";
                    };
                    dbName = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Database name for this user";
                    };
                    dbUser = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Database user name";
                    };
                  };

                  config = {
                    generateSecrets = lib.mkIf config.installSecrets true;
                  };
                }
              )
            );
          };
        };
      };

      config = {
        toh.overlays.cli-patroni-user = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [
            pkgs.postgresql
            pkgs.vault
          ];
          extraTextFile = ./users.nu;
          extraTextVariables = {
            TOH_PATRONI_USERS = builtins.toJSON config.toh.services.patroni.users;
            TOH_PATRONI_SUPERUSERS = builtins.toJSON (builtins.attrValues tohLib.patroni.superusers);
          };
        };

        toh.services.patroni.init.sql.files = mergeByUser (
          {
            user,
            installSecrets,
            isSuperuser,
            ...
          }:
          lib.mkBefore [
            (lib.mkIf (installSecrets && !isSuperuser) {
              ${user} = config.toh.meta.sops.secrets."patroni-${user}-init".path;
            })
          ]
        );

        toh.meta.sops.secrets = mergeByUser (
          {
            user,
            installSecrets,
            env,
            url,
            ca,
            crt,
            key,
            password,
            isSuperuser,
            owner,
            group,
            ...
          }:
          lib.mkIf installSecrets {
            "patroni-${user}-ca" = {
              inherit owner group;
              key = "openssl-ca-public";
              path = ca;
              mode = "0644";
            };
            "patroni-${user}-public" = {
              inherit owner group;
              path = crt;
              mode = "0644";
            };
            "patroni-${user}-private" = {
              inherit owner group;
              path = key;
              mode = "0400";
            };
            "patroni-${user}-env" = {
              inherit owner group;
              path = env;
              mode = "0400";
            };
            "patroni-${user}-url" = {
              inherit owner group;
              path = url;
              mode = "0400";
            };
            "patroni-${user}-init" = lib.mkIf (!isSuperuser) {
              owner = config.systemd.services.patroni.serviceConfig.User;
              group = config.systemd.services.patroni.serviceConfig.Group;
              mode = "0400";
            };
            "patroni-${user}-pass" = {
              inherit owner group;
              path = password;
              mode = "0400";
            };
          }
        );

        toh.meta.cryl.machine = mergeByUser (
          {
            user,
            generateSecrets,
            isSuperuser,
            ca,
            crt,
            key,
            dbName,
            dbUser,
            ...
          }:
          lib.mkIf generateSecrets [
            {
              "patroni-${user}" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      renew = true;
                      from = "cluster/patroni-${user}-pass";
                      to = "patroni-${user}-pass";
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = user;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "patroni-${user}-cert-config";
                      request_config = "patroni-${user}-cert-request-config";
                      private = "patroni-${user}-private";
                      request = "patroni-${user}-cert-request";
                      ca_private = "cluster/openssl-ca-private";
                      ca_public = "cluster/openssl-ca-public";
                      serial = "cluster/openssl-ca-serial";
                      public = "patroni-${user}-public";
                      renew = true;
                    };
                  }
                  {
                    generator = "mustache";
                    arguments = {
                      name = "patroni-${user}-env";
                      renew = true;
                      listing = {
                        type = "map";
                        value = {
                          PATRONI_USER_PASS = "cluster/patroni-${user}-pass";
                        };
                      };
                      template = ''
                        PGHOST="${proxyAttrs.host}"
                        PGPORT="${builtins.toString proxyAttrs.port}"
                        PGUSER="${dbUser}"
                        PGPASSWORD="{{{PATRONI_USER_PASS}}}"
                        PGSSLMODE="verify-full"
                        PGSSLROOTCERT="${ca}"
                        PGSSLCERT="${crt}"
                        PGSSLKEY="${key}"
                      ''
                      + (lib.optionalString (!isSuperuser) ''
                        PGDATABASE="${dbName}"
                      '');
                    };
                  }
                  {
                    generator = "mustache";
                    arguments = {
                      name = "patroni-${user}-url";
                      renew = true;
                      listing = {
                        type = "map";
                        value = {
                          PATRONI_USER_PASS = "cluster/patroni-${user}-pass";
                        };
                      };
                      template = tohLib.url.makeUrl {
                        protocol = "postgresql";
                        inherit (proxyAttrs) host port;
                        user = dbUser;
                        password = "{{{PATRONI_USER_PASS}}}";
                        path = if isSuperuser then null else dbName;
                        parameters = {
                          sslmode = "verify-full";
                          sslrootcert = ca;
                          sslcert = crt;
                          sslkey = key;
                        };
                      };
                    };
                  }
                  (lib.mkIf (!isSuperuser) {
                    generator = "mustache";
                    arguments = {
                      name = "patroni-${user}-init";
                      renew = true;
                      listing = {
                        type = "map";
                        value = {
                          PATRONI_USER_PASS = "patroni-${user}-pass";
                        };
                      };
                      template = ''
                        select 'create user ${dbUser} with password '''{{PATRONI_USER_PASS}}''''
                        where not exists (select from pg_catalog.pg_roles where rolname = '${dbUser}')\gexec

                        select 'create database ${dbName}'
                        where not exists (select from pg_database where datname = '${dbName}')\gexec

                        \c ${dbName}

                        alter default privileges in schema public grant all on tables to ${dbUser};
                        alter default privileges in schema public grant all on sequences to ${dbUser};
                        alter default privileges in schema public grant all on functions to ${dbUser};
                        alter default privileges in schema public grant all on types to ${dbUser};

                        grant usage on schema public to ${dbUser};
                        grant create on schema public to ${dbUser};

                        grant all on all tables in schema public to ${dbUser};
                        grant all on all sequences in schema public to ${dbUser};
                        grant all on all functions in schema public to ${dbUser};
                      '';
                    };
                  })
                ];
              };
            }
          ]
        );

        toh.meta.cryl.cluster = mergeByUser (
          {
            user,
            generateSecrets,
            dbUser,
            ...
          }:
          lib.mkIf generateSecrets [
            {
              "patroni-${user}" = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "patroni-${user}-pass";
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = dbUser;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "patroni-${user}-cert-config";
                      request_config = "patroni-${user}-cert-request-config";
                      private = "patroni-${user}-private";
                      request = "patroni-${user}-cert-request";
                      ca_private = "openssl-ca-private";
                      ca_public = "openssl-ca-public";
                      serial = "openssl-ca-serial";
                      public = "patroni-${user}-public";
                      renew = true;
                    };
                  }
                ];
              };
            }
          ]
        );

        toh.services.patroni.createUserGroup = mergeByUser (
          { installSecrets, ... }: lib.mkIf installSecrets true
        );

        toh.pki.generateCa = mergeByUser ({ generateSecrets, ... }: lib.mkIf generateSecrets true);
      };
    };
}
