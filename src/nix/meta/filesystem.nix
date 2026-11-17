# TODO: instances

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
                { name, config, ... }:
                {
                  options = {
                    directory = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      defaultText = lib.literalExpression "name";
                      description = "Mount from a subdirectory of the filesystem";
                    };
                    erase = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Erase existing directory before mounting";
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
                    share = lib.mkOption {
                      description = "SMB share options for mount";
                      default = null;
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            name = lib.mkOption {
                              type = lib.types.str;
                              default = builtins.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" name);
                              defaultText = lib.literalExpression ''builtins.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" name)'';
                              description = "Share name";
                            };
                            fileMask = lib.mkOption {
                              type = lib.types.str;
                              default = "0644";
                              description = "File creation mask";
                            };
                            directoryMask = lib.mkOption {
                              type = lib.types.str;
                              default = "0755";
                              description = "Directory creation mask";
                            };
                          };
                        }
                      );
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
