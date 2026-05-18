{
  toh.lib.nixosModules.meta-filesystem =
    { lib, tohLib, ... }:
    {
      options.toh.meta = {
        filesystem = {
          type = lib.mkOption {
            type = lib.types.enum tohLib.filesystem.types;
            description = "Filesystem type";
          };

          mounts = lib.mkOption {
            description = "Filesystem mounts by mount paths";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule (
                { config, ... }:
                {
                  options = {
                    directory = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Mount from a subdirectory of the filesystem";
                    };
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = "root";
                      description = "User owner of this mount";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      default = config.user;
                      description = "Group owner of this mount";
                    };
                    mode = lib.mkOption {
                      type = lib.types.str;
                      default = "0750";
                      description = "Mount permission mode";
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
