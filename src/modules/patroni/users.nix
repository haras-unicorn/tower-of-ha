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

                isSuperuser = builtins.elem name tohLib.patroni.superusers.names;

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
                      builtins.elem name tohLib.patroni.superusers.names
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
            config.services.patroni.postgresqlPackage
            pkgs.vault
          ];
          extraTextFile = ./user.nu;
          extraTextVariables = {
            TOH_PATRONI_USERS_TO_ENV_PATHS = builtins.toJSON (
              builtins.mapAttrs (_: { env, ... }: env) config.toh.services.patroni.users
            );
            TOH_PATRONI_SUPERUSERS = builtins.toJSON tohLib.patroni.superusers.names;
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
              ${user} = config.sops.secrets."patroni-${user}-init".path;
            })
          ]
        );

        sops.secrets = mergeByUser (
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
              key = "patroni-ca-public";
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

        toh.cryl.machine = mergeByUser (
          {
            user,
            generateSecrets,
            isSuperuser,
            ca,
            crt,
            key,
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
                      ca_private = "cluster/patroni-ca-private";
                      ca_public = "cluster/patroni-ca-public";
                      serial = "cluster/patroni-ca-serial";
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
                        PGUSER="${user}"
                        PGPASSWORD="{{{PATRONI_USER_PASS}}}"
                        PGSSLMODE="verify-full"
                        PGSSLROOTCERT="${ca}"
                        PGSSLCERT="${crt}"
                        PGSSLKEY="${key}"
                      ''
                      + (lib.optionalString (!isSuperuser) ''
                        PGDATABASE="${user}"
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
                        inherit user;
                        password = "{{{PATRONI_USER_PASS}}}";
                        path = user;
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
                        select 'create user ${user} with password '''{{PATRONI_USER_PASS}}''''
                        where not exists (select from pg_catalog.pg_roles where rolname = '${user}')\gexec

                        select 'create database ${user}'
                        where not exists (select from pg_database where datname = '${user}')\gexec

                        \c ${user}

                        alter default privileges in schema public grant all on tables to ${user};
                        alter default privileges in schema public grant all on sequences to ${user};
                        alter default privileges in schema public grant all on functions to ${user};
                        alter default privileges in schema public grant all on types to ${user};

                        grant usage on schema public to ${user};
                        grant create on schema public to ${user};

                        grant all on all tables in schema public to ${user};
                        grant all on all sequences in schema public to ${user};
                        grant all on all functions in schema public to ${user};
                      '';
                    };
                  })
                ];
              };
            }
          ]
        );

        toh.cryl.cluster = mergeByUser (
          { user, generateSecrets, ... }:
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
                      ca_private = "patroni-ca-private";
                      ca_public = "patroni-ca-public";
                      serial = "patroni-ca-serial";
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

        toh.services.patroni.generateCa = mergeByUser (
          { generateSecrets, ... }: lib.mkIf generateSecrets true
        );
      };
    };
}
