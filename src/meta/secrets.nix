{
  toh.lib.nixosModules.meta-secrets =
    {
      lib,
      tohLib,
      config,
      ...
    }:
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
            mount = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.mount;
              description = "Secrets mount";
            };
            cluster = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.cluster;
              description = "Secrets cluster key folder";
            };
            machines = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.machines;
              description = "Secrets machines key folder";
            };
            external = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.external;
              description = "Secrets external key folder";
            };
            root = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.root;
              description = "Secrets root key folder";
            };
            age = lib.mkOption {
              type = lib.types.str;
              default = tohLib.secrets.keys.age;
              description = "Secrets age key";
            };
          };

          files = {
            age = lib.mkOption {
              type = lib.types.str;
              description = "Age key location";
            };
            sops = lib.mkOption {
              type = lib.types.str;
              description = "Sops file location";
            };
            token = lib.mkOption {
              type = lib.types.str;
              description = "Secret store token location";
            };
            response = lib.mkOption {
              type = lib.types.str;
              description = "Secret store token response location";
            };
            metadata = lib.mkOption {
              type = lib.types.str;
              description = "Secret store metadata location";
            };
            root = lib.mkOption {
              type = lib.types.str;
              description = "Secret store root location";
            };
          };
        };
      };
    };
}
