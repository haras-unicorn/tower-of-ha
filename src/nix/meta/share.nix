{
  self.nixosModules.meta-share.flake = true;
  self.nixosModules.meta-share.value =
    { lib, ... }:
    {
      options.toh.meta = {
        share = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "File share host (via proxy)";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "File share port (via proxy)";
          };

          apps = lib.mkOption {
            default = { };
            description = ''
              App registration for ToH file shares. Every app gets a share and
              a user of its own, both named after the app.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application share secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application share secrets owner linux group";
                    };
                  };
                }
              )
            );
          };

          shares = lib.mkOption {
            description = "File shares of the apps on this machine";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Share name";
                  };

                  user = lib.mkOption {
                    type = lib.types.str;
                    description = "Share user name";
                  };

                  password = lib.mkOption {
                    type = lib.types.path;
                    description = "Path to the share user password";
                  };
                };
              }
            );
          };
        };
      };
    };
}
