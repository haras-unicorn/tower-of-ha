{
  toh.lib.nixosModules.meta-email =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        email = {
          domain = lib.mkOption {
            type = lib.types.str;
            default = "email.${config.toh.meta.domains.topLevel}";
            description = "Email domain.";
          };

          admin = lib.mkOption {
            type = lib.types.str;
            description = "Admin email address.";
          };

          apps = lib.mkOption {
            default = { };
            description = "Static email inbox registrations for services";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Email user owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Email user owner linux group";
                    };
                  };
                }
              )
            );
          };

          emails = lib.mkOption {
            default = { };
            description = "Email inboxes for services";
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  address = lib.mkOption {
                    type = lib.types.str;
                    description = "Email address";
                  };

                  password = lib.mkOption {
                    type = lib.types.path;
                    description = "Path to email user password";
                  };
                };
              }
            );
          };
        };
      };
    };
}
