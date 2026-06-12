{
  toh.lib.nixosModules.meta-s3 =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        s3 = {
          protocol = lib.mkOption {
            type = lib.types.enum tohLib.s3.protocols;
            description = "S3 protocol";
          };

          host = lib.mkOption {
            type = lib.types.str;
            description = "S3 host";
          };

          port = lib.mkOption {
            type = lib.types.port;
            description = "S3 port";
          };

          region = lib.mkOption {
            type = lib.types.str;
            description = "S3 region";
          };

          apps = lib.mkOption {
            default = { };
            description = "App registration for ToH S3 store";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application secrets owner linux group";
                    };
                  };
                }
              )
            );
          };

          buckets = lib.mkOption {
            default = { };
            description = "Bucket registration for ToH S3 store";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { ... }:
                {
                  options = {
                    keyId = lib.mkOption {
                      type = lib.types.str;
                      description = "S3 key id file path";
                    };

                    secretKey = lib.mkOption {
                      type = lib.types.str;
                      description = "S3 secret key file path";
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
