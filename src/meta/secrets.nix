{
  toh.lib.nixosModules.meta-secrets =
    { lib, tohLib, ... }:
    {
      options.toh.meta = {
        secrets = {
          directories = {
            cluster = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.directories.cluster;
              description = "Secrets cluster directory";
            };
            machines = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.directories.machines;
              description = "Secrets machines directory";
            };
            external = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.directories.external;
              description = "Secrets external directory";
            };
          };

          keys = {
            cluster = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.cluster;
              description = "Secrets cluster key";
            };
            machines = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.machines;
              description = "Secrets machines key";
            };
            external = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.external;
              description = "Secrets external key";
            };
          };
        };
      };
    };
}
