{
  toh.lib.nixosModules.meta-git =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    {
      options.toh.meta = {
        git = {
          http = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Git HTTP host (via proxy)";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 443;
              description = "Git HTTP port (via proxy)";
            };
          };

          ssh = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Git SSH host (via proxy)";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "Git SSH port (via proxy)";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "forgejo";
              description = "Git SSH user";
            };
          };

          apps = lib.mkOption {
            default = { };
            description = "App registration for ToH git service";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application git secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application git secrets owner linux group";
                    };
                  };
                }
              )
            );
          };

          url = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = "https://${config.toh.meta.git.http.host}";
            defaultText = lib.literalExpression ''"https://''${config.toh.meta.git.http.host}"'';
            description = "Git service base URL (derived from HTTP host)";
          };
        };
      };
    };
}
