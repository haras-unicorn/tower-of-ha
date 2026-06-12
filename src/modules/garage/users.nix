{
  toh.lib.nixosModules.services-garage-users =
    {
      lib,
      config,
      pkgs,
      tohLib,
      ...
    }:
    let
      osUsers = config.users.users;

      cfg = config.toh.services.garage;

      usersList = builtins.map (
        { name, value }:
        value
        // {
          inherit name;
          owner = value.user;
        }
      ) (lib.attrsToList cfg.users);

      mergeByUser = forEachUser: lib.mkMerge (builtins.map forEachUser usersList);
    in
    {
      options.toh.services = {
        garage = {
          users = lib.mkOption {
            default = { };
            description = "Garage S3 users";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, config, ... }:
                let
                  certs =
                    if !builtins.elem name (builtins.attrNames osUsers) || osUsers.${name}.home == "/var/empty" then
                      "${tohLib.garage.certs.root}/${name}"
                    else
                      builtins.replaceStrings [ "~" ] [ osUsers.${name}.home ] tohLib.garage.certs.user;
                in
                {
                  options = {
                    installSecrets = lib.mkEnableOption "garage user secrets installation";

                    generateSecrets = lib.mkEnableOption "garage user secrets generation";

                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "User owner of secrets";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Group owner of secrets";
                    };
                    keyId = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.garage.certs.keyId}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.garage.certs.keyId}"'';
                      description = "Path to S3 key id file";
                    };
                    secretKey = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${tohLib.garage.certs.secretKey}";
                      defaultText = lib.literalExpression ''"${certs}/${tohLib.garage.certs.secretKey}"'';
                      description = "Path to S3 secret key file";
                    };
                  };

                  config = {
                    generateSecrets = lib.mkIf config.installSecrets true;
                  };
                }
              )
            );
          };
        };
      };

      config = {
        toh.overlays.cli-s3-users = tohLib.cli.makeOverlay {
          extraRuntimeInputs = (final: [ final.s3cmd ]);
          extraTextFile = ./users.nu;
          extraTextVariables = {
            TOH_S3_USERS = builtins.toJSON cfg.users;
          };
        };

        sops.secrets = mergeByUser (
          {
            user,
            installSecrets,
            keyId,
            secretKey,
            owner,
            group,
            ...
          }:
          lib.mkIf installSecrets {
            "garage-key-${user}-id" = {
              inherit owner group;
              path = keyId;
              mode = "0400";
            };
            "garage-key-${user}-secret" = {
              inherit owner group;
              path = secretKey;
              mode = "0400";
            };
          }
        );

        toh.cryl.machine = mergeByUser (
          {
            user,
            generateSecrets,
            ...
          }:
          lib.mkIf generateSecrets ([
            {
              "garage-key-${user}" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-key-${user}-id";
                      to = "garage-key-${user}-id";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-key-${user}-secret";
                      to = "garage-key-${user}-secret";
                    };
                  }
                ];
              };
            }
          ])
        );

        toh.cryl.cluster = mergeByUser (
          { user, generateSecrets, ... }:
          lib.mkIf generateSecrets [
            {
              "garage-key-${user}" = {
                generations = [
                  {
                    generator = "script";
                    arguments = {
                      name = "garage-key-${user}-id-script";
                      renew = true;
                      text = ''$"GK(openssl rand -hex 12)" | save -f garage-key-${user}-id'';
                    };
                  }
                  {
                    generator = "script";
                    arguments = {
                      name = "garage-key-${user}-secret-script";
                      renew = true;
                      text = ''$"(openssl rand -hex 32)" | save -f garage-key-${user}-secret'';
                    };
                  }
                ];
              };
            }
          ]
        );

        toh.services.garage.createUserGroup = mergeByUser (
          { installSecrets, ... }: lib.mkIf installSecrets true
        );

        toh.services.garage.init.keys = mergeByUser (
          {
            user,
            generateSecrets,
            keyId,
            secretKey,
            ...
          }:
          lib.mkIf generateSecrets [
            {
              inherit keyId secretKey;
            }
          ]
        );

        toh.services.garage.init.buckets = mergeByUser (
          {
            name,
            generateSecrets,
            keyId,
            ...
          }:
          lib.mkIf generateSecrets [
            {
              bucket = name;
              inherit keyId;
            }
          ]
        );
      };
    };
}
