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
            type = lib.types.enum tohLib.database.protocols;
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
                      default = name;
                      description = "Application secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application secrets owner linux group";
                    };

                    init = {
                      sql = {
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

                      systemd = {
                        unit = lib.mkOption {
                          type = lib.types.nullOr lib.types.str;
                          default = null;
                          description = "Systemd unit to execute during initialization of database";
                        };
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
                    password = lib.mkOption {
                      type = lib.types.str;
                      description = "Database user password file path";
                    };

                    ssl.ca = lib.mkOption {
                      type = lib.types.path;
                      description = "Database SSL CA path";
                    };

                    ssl.crt = lib.mkOption {
                      type = lib.types.path;
                      description = "Database certificate path";
                    };

                    ssl.key = lib.mkOption {
                      type = lib.types.path;
                      description = "Database certificate key path";
                    };

                    parameters = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "Database URL parameters";
                    };

                    url = lib.mkOption {
                      type = lib.types.str;
                      description = "Database URL file path";
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
