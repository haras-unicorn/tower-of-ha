{
  toh.lib.nixosModules.meta-sops =
    {
      lib,
      config,
      options,
      ...
    }:
    {
      options.toh.meta = {
        sops = {
          secrets = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, config, ... }: {
                  options = {
                    key = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                    };

                    path = lib.mkOption {
                      type = lib.types.str;
                      default = "/run/secrets/${name}";
                    };

                    mode = lib.mkOption {
                      type = lib.types.str;
                      default = "0400";
                    };

                    owner = lib.mkOption {
                      type = with lib.types; nullOr str;
                      default = null;
                    };

                    group = lib.mkOption {
                      type = with lib.types; nullOr str;
                      default = null;
                    };

                    restartUnits = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };

                    reloadUnits = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                    };
                  };
                }
              )
            );
            default = { };
            description = ''
              Secrets to decrypt and install with sops-nix.
            '';
          };
        };
      };
    };
}
