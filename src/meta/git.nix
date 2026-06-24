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
          host = lib.mkOption {
            type = lib.types.str;
            default = "git.${config.toh.meta.domains.service}";
            defaultText = lib.literalExpression ''"git.''${config.toh.meta.domains.service}"'';
            description = "Git service host";
          };

          httpPort = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Git HTTP port (via proxy)";
          };

          sshPort = lib.mkOption {
            type = lib.types.port;
            default = 22;
            description = "Git SSH port";
          };

          url = lib.mkOption {
            type = lib.types.str;
            default = "https://${config.toh.meta.git.host}";
            defaultText = lib.literalExpression ''"https://''${config.toh.meta.git.host}"'';
            description = "Git service base URL";
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
        };
      };
    };
}
