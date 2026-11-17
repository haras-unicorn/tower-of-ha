{
  toh.lib.nixosModules.meta-domains =
    { lib, ... }:
    {
      options.toh.meta = {
        domains = {
          machineSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Machine WAN domain secret.
            '';
          };

          topLevel = lib.mkOption {
            type = lib.types.str;
            description = ''
              Top-level domain.
            '';
          };

          service = lib.mkOption {
            type = lib.types.str;
            description = ''
              Service domain.
            '';
          };

          node = lib.mkOption {
            type = lib.types.str;
            description = ''
              Node domain.
            '';
          };
        };
      };
    };
}
