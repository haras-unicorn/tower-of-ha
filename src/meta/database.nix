{
  toh.lib.nixosModules.meta-database =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        database = {
          protocol = lib.mkOption {
            type = lib.types.str;
            description = "Database protocol";
          };

          host = lib.mkOption {
            type = lib.types.str;
            description = "Database host";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "Database port";
          };

          apps = lib.mkOption {
            default = { };
            description = "App registration for ToH database";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      description = "Application linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      description = "Application linux group";
                    };

                    init = {
                      sql = {
                        secrets = lib.mkOption {
                          type = lib.types.attrsOf lib.types.str;
                          default = { };
                          description = "SOPS secrets to use to generate initialization SQL script";
                        };

                        script = lib.mkOption {
                          type = lib.types.nullOr lib.types.str;
                          default = null;
                          description = "SQL string to execute during initialization of database";
                        };

                        file = lib.mkOption {
                          type = lib.types.nullOr lib.types.path;
                          default = null;
                          description = "SQL file path to execute during initialization of database";
                        };
                      };

                      nushell = {
                        script = lib.mkOption {
                          type = lib.types.nullOr lib.types.str;
                          default = null;
                          description = "Nushell string to execute during initialization of database";
                        };

                        file = lib.mkOption {
                          type = lib.types.nullOr lib.types.path;
                          default = null;
                          description = "Nushell file path to execute during initialization of database";
                        };
                      };
                    };

                    secrets = {
                      generations = lib.mkOption {
                        type = lib.types.listOf lib.types.raw;
                        default = [ ];
                        description = "Generations to run after database secrets for this app have been generated";
                      };
                    };
                  };
                }
              )
            );
          };

          instances = lib.mkOption {
            default = { };
            description = "Instance registration for ToH database";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Database user";
                    };

                    passwordSecret = lib.mkOption {
                      type = lib.types.str;
                      description = "Database user password SOPS secret";
                    };

                    passwordPath = lib.mkOption {
                      type = lib.types.str;
                      description = "Database user password file path";
                    };

                    name = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Database instance name";
                    };

                    parameters = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = "Database URL parameters";
                    };

                    urlPath = lib.mkOption {
                      type = lib.types.str;
                      description = "Database URL file path";
                    };

                    urlSecret = lib.mkOption {
                      type = lib.types.str;
                      description = "Database URL SOPS secret";
                    };
                  };
                }
              )
            );
          };
        };
      };
    };
}
