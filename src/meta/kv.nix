{
  toh.lib.nixosModules.meta-kv =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        kv = {
          protocol = lib.mkOption {
            type = lib.types.enum tohLib.kv.protocols;
            description = "KV store protocol";
          };

          host = lib.mkOption {
            type = lib.types.str;
            description = "KV store host";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "KV store port";
          };

          apps = lib.mkOption {
            default = { };
            description = "App registration for ToH KV store";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application secrets owner linux group";
                    };

                    prefix = lib.mkOption {
                      type = lib.types.oneOf [
                        lib.types.str
                        (lib.types.enum [
                          "all"
                          "none"
                        ])
                      ];
                      default = "all";
                      description = "Key prefix for the ACL user";
                    };

                    database = lib.mkOption {
                      type = lib.types.oneOf [
                        lib.types.ints.unsigned
                        (lib.types.enum [
                          "all"
                          "none"
                        ])
                      ];
                      description = "Database for ACL user";
                    };

                    permissions = lib.mkOption {
                      type = lib.types.listOf (lib.types.enum (builtins.attrValues tohLib.kv.permissions));
                      default = [ tohLib.kv.permissions.all ];
                      description = "Permissions for ACL user";
                    };
                  };
                }
              )
            );
          };

          instances = lib.mkOption {
            default = { };
            description = "Instance registration for ToH KV store";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { ... }:
                {
                  options = {
                    password = lib.mkOption {
                      type = lib.types.str;
                      description = "KV store user password file path";
                    };

                    url = lib.mkOption {
                      type = lib.types.str;
                      description = "KV store URL file path";
                    };

                    prefix = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "KV store key prefix to use";
                    };

                    database = lib.mkOption {
                      type = lib.types.nullOr lib.types.ints.unsigned;
                      default = null;
                      description = "KV store database index to use";
                    };

                    ssl.ca = lib.mkOption {
                      type = lib.types.path;
                      description = "KV store CA path";
                    };

                    ssl.crt = lib.mkOption {
                      type = lib.types.path;
                      description = "KV store certificate path";
                    };

                    ssl.key = lib.mkOption {
                      type = lib.types.path;
                      description = "KV store certificate key path";
                    };

                    parameters = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "KV store URL parameters";
                    };
                  };
                }
              )
            );
          };
        };
      };

      config = {
        assertions = [
          (
            let
              databases = builtins.concatMap (
                { database, ... }: lib.optional (builtins.isInt database) database
              ) (builtins.attrValues config.toh.meta.kv.apps);
            in
            {
              assertion = databases == (lib.unique databases);
              message =
                "Duplicate KV databases requested: "
                + builtins.concatStringsSep ", " (builtins.map builtins.toString databases);
            }
          )
        ];
      };
    };
}
