{
  toh.lib.nixosModules.meta-user =
    { lib, ... }:
    {
      options.toh.meta = {
        user = {
          user = lib.mkOption {
            type = lib.types.str;
            description = ''
              User name.
            '';
          };
          group = lib.mkOption {
            type = lib.types.str;
            description = ''
              User group name.
            '';
          };
          uid = lib.mkOption {
            type = lib.types.ints.unsigned;
            description = ''
              User id.
            '';
          };
          gid = lib.mkOption {
            type = lib.types.ints.unsigned;
            description = ''
              User group id.
            '';
          };
          home = lib.mkOption {
            type = lib.types.path;
            description = ''
              User home path.
            '';
          };
          generatedPassword = lib.mkOption {
            type = lib.types.bool;
            description = ''
              Whether the user uses a generated password.
            '';
          };
        };
      };
    };
}
