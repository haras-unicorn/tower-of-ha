{
  toh.lib.test.testModules.domains =
    { lib, ... }:
    {
      options.toh.test = {
        domains = {
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

      config = {
        toh.test.domains = {
          topLevel = "toh";
          service = "service.toh";
          node = "node.toh";
        };

        defaults = {
          toh.meta.domains = {
            topLevel = "toh";
            service = "service.toh";
            node = "node.toh";
          };
        };
      };
    };
}
