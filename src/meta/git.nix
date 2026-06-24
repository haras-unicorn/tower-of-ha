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
            description = "Git service host";
          };

          httpPort = lib.mkOption {
            type = lib.types.port;
            description = "Git HTTP port (via proxy)";
          };

          sshPort = lib.mkOption {
            type = lib.types.port;
            description = "Git SSH port";
          };
        };
      };
    };
}
