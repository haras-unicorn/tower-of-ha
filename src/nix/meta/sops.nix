{
  self.nixosModules.meta-sops.flake = true;
  self.nixosModules.meta-sops.value =
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

                    public = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = ''
                        Whether the value may be read by everyone, like a
                        certificate; sops carries it because cryl makes it
                        together with its private key.
                      '';
                    };

                    mode = lib.mkOption {
                      type = lib.types.str;
                      default = if config.public then "0644" else "0400";
                    };

                    owner = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };

                    group = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
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
