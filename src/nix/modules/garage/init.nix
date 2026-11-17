{
  toh.lib.nixosModules.services-garage-init =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.garage;
    in
    {
      options.toh.services = {
        garage = {
          init = {
            enable = lib.mkEnableOption "Garage cluster and bucket initialization" // {
              default = cfg.enable;
            };

            keys = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    keyId = lib.mkOption {
                      type = lib.types.path;
                      description = "Path to key ID file";
                    };
                    secretKey = lib.mkOption {
                      type = lib.types.path;
                      description = "Path to the secret key file";
                    };
                  };
                }
              );
              default = [ ];
              description = "Keys to import into garage";
            };

            buckets = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    bucket = lib.mkOption {
                      type = lib.types.str;
                      description = "Bucket name";
                    };
                    keyId = lib.mkOption {
                      type = lib.types.path;
                      description = "Key ID to authorize the bucket with";
                    };
                  };
                }
              );
              default = [ ];
              description = "Buckets to create and authorize keys for";
            };
          };
        };
      };

      config = lib.mkIf cfg.init.enable {
        toh.overlays = tohLib.cli.makeOverlays {
          name = "garage-init";
          runtimeInputs = (pkgs: [ pkgs.garage ]);
          textFile = ./init.nu;
          textVariables = {
            TOH_GARAGE_INIT_KEYS = builtins.toJSON cfg.init.keys;
            TOH_GARAGE_INIT_BUCKETS = builtins.toJSON cfg.init.buckets;
            TOH_GARAGE_INIT_LAYOUT_VERSION = "1";
            TOH_GARAGE_INIT_CAPACITY = "${builtins.toString cfg.capacityInMB}MB";
          };
        };

        systemd.services.garage-initialization = {
          description = "Garage cluster and bucket initialization";
          wantedBy = [ "garage.service" ];
          bindsTo = [ "garage.service" ];
          after = [ "garage.service" ];
          path = [ pkgs.tohPackages.garage-init ];
          script = "garage-init";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
          };
          environment = {
            GARAGE_RPC_SECRET_FILE = config.toh.meta.sops.secrets."garage-rpc-secret".path;
            GARAGE_ADMIN_TOKEN_FILE = config.toh.meta.sops.secrets."garage-admin-token".path;
          };
        };

        systemd.targets.toh-s3-online = {
          wantedBy = [ "garage-initialization.service" ];
          bindsTo = [ "garage-initialization.service" ];
          after = [ "garage-initialization.service" ];
        };
      };
    };
}
