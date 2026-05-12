# TODO: login per machine

{
  toh.lib.nixosModules.services-cockroachdb-apps =
    {
      lib,
      config,
      tohLib,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;

      machines = tohLib.serviceMachines "cockroachdb";

      anyMachines = tohLib.anyServiceMachines "cockroachdb";

      apps = builtins.zipAttrsWith (_: builtins.head) (
        builtins.map (
          machine:
          builtins.mapAttrs (
            name: value: value // { certs = "/etc/cockroachdb/apps/${name}/certs"; }
          ) machine.config.toh.meta.database.apps
        ) config.toh.cluster.machinea
      );

      user = config.toh.meta.user.user;
    in
    {
      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.database = {
            host = builtins.concatStringsSep "," (
              builtins.map (machine: config.services.cockroachdb.sql.address) machines
            );
            port = builtins.concatStringsSep "," (
              builtins.map (machine: builtins.toString config.services.cockroachdb.sql.port) machines
            );
            protocol = "postgresql://";
          };

          toh.meta.database.instances = builtins.mapAttrs (name: value: {
            user = name;
            passwordSecret = "cockroach-${name}-pass";
            passwordPath = config.sops.secrets."cockroach-${name}-pass".path;
            name = name;
            parameters =
              "?sslmode=verify-full"
              + "&sslrootcert=${value.certs}/ca.crt"
              + "&sslcert=${value.certs}/client.${name}.crt"
              + "&sslkey=${value.certs}/client.${name}.key";
            urlPath = config.sops.secrets."cockroach-${name}-url".path;
            urlSecret = "cockroach-${name}-url";
          }) apps;

          sops.secrets = builtins.listToAttrs (
            builtins.concatMap (
              { name, value }:
              [
                {
                  name = "cockroach-${name}-pass";
                  value = {
                    owner = value.user;
                    group = value.group;
                    mode = "0400";
                  };
                }
                {
                  name = "cockroach-${name}-ca-public";
                  value = {
                    key = "cockroach-ca-public";
                    path = "${value.certs}/ca.crt";
                    owner = value.user;
                    group = value.group;
                    mode = "0400";
                  };
                }

                {
                  name = "cockroach-${name}-private";
                  value = {
                    path = "${value.certs}/client.${name}.key";
                    owner = value.user;
                    group = value.group;
                    mode = "0400";
                  };
                }
                {
                  name = "cockroach-${name}-public";
                  value = {
                    path = "${value.certs}/client.${name}.crt";
                    owner = value.user;
                    group = value.group;
                    mode = "0400";
                  };
                }
                {
                  name = "cockroach-${name}-url";
                  value = {
                    owner = value.user;
                    group = value.group;
                    mode = "0400";
                  };
                }
              ]
            ) (lib.attrsToList apps)
          );

          toh.cryl.machine.cockroachdb-apps-client = {
            generations = builtins.concatMap (
              { name, value }:
              [
                {
                  generator = "cockroach-client-cert";
                  arguments = {
                    renew = true;
                    ca_private = "cockroach-ca-private";
                    ca_public = "cockroach-ca-public";
                    private = "cockroach-${name}-private";
                    public = "cockroach-${name}-public";
                    user = name;
                  };
                }
                {
                  generator = "mustache";
                  arguments = {
                    name = "cockroach-${name}-url";
                    renew = true;
                    listing = {
                      type = "map";
                      value = {
                        COCKROACH_APP_PASS = "cluster/cockroach-${name}-pass";
                      };
                    };
                    template =
                      "postgresql://${name}:{{COCKROACH_APP_PASS}}"
                      + "@${config.toh.meta.database.host}"
                      + ":${builtins.toString config.toh.meta.database.port}"
                      + "/${name}"
                      + "?sslmode=verify-full"
                      + "&sslrootcert=${value.certs}/ca.crt"
                      + "&sslcert=${value.certs}/client.${name}.crt"
                      + "&sslkey=${value.certs}/client.${name}.key";
                  };
                }
              ]
              ++ value.secrets.generations
            ) (lib.attrsToList apps);
          };

          toh.cryl.cluster.cockroachdb-apps = {
            generations = builtins.map (name: {
              generator = "key";
              arguments = {
                name = "cockroach-${name}-pass";
              };
            }) (builtins.attrNames apps);
          };

          toh.services.cockroachdb.generateCa = true;
        })
        (lib.mkIf cfg.enable {
          services.cockroachdb.init.sql.files = lib.flatten (
            builtins.map (
              { name, value }:
              [
                config.sops.secrets."cockroach-${name}-init".path
              ]
            ) (lib.attrsToList apps)
          );

          services.cockroachdb.init.nushell.scripts = builtins.filter builtins.isString (
            builtins.map (app: app.init.nushell.script) (builtins.attrValues apps)
          );

          services.cockroachdb.init.nushell.files = builtins.filter builtins.isString (
            builtins.map (app: app.init.nushell.file) (builtins.attrValues apps)
          );

          sops.secrets = builtins.listToAttrs (
            builtins.concatMap (
              { name, value }:
              [
                {
                  name = "cockroach-${name}-init";
                  value = {
                    owner = config.services.cockroachdb.user;
                    group = config.services.cockroachdb.group;
                    mode = "0400";
                  };
                }
              ]
            ) (lib.attrsToList apps)
          );

          toh.cryl.machine.cockroachdb-apps-init = {
            generations = builtins.concatMap (
              { name, value }:
              [
                {
                  generator = "mustache";
                  arguments = {
                    name = "cockroach-${name}-init";
                    renew = true;
                    listing = {
                      type = "map";
                      value = {
                        COCKROACH_APP_PASS = "cluster/cockroach-${name}-pass";
                      }
                      // value.init.sql.secrets;
                    };
                    template = ''
                      create database if not exists ${name};

                      \c ${name}


                      create user if not exists ${name} password '{{COCKROACH_APP_PASS}}';

                      alter default privileges for all roles in schema public grant all on tables to ${name};
                      alter default privileges for all roles in schema public grant all on sequences to ${name};
                      alter default privileges for all roles in schema public grant all on functions to ${name};

                      grant all on all tables in schema public to ${name};
                      grant all on all sequences in schema public to ${name};
                      grant all on all functions in schema public to ${name};


                      alter default privileges for all roles in schema public grant all on tables to ${user};
                      alter default privileges for all roles in schema public grant all on sequences to ${user};
                      alter default privileges for all roles in schema public grant all on functions to ${user};

                      grant all on all tables in schema public to ${user};
                      grant all on all sequences in schema public to ${user};
                      grant all on all functions in schema public to ${user};


                      ${if value.init.sql.script != null then value.init.sql.script else ""}

                      ${if value.init.sql.file != null then "\i ${value.init.sql.file}" else ""}
                    '';
                  };
                }
              ]
              ++ value.secrets.generations
            ) (lib.attrsToList apps);
          };
        })
      ];
    };
}
