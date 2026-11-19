{ selfLib, ... }:

{
  self.nixosModules.services-garage-users.flake = true;
  self.nixosModules.services-garage-users.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      osUsers = config.users.users;

      cfg = config.toh.services.garage;

      runsGarage = cfg.enable;

      initKeyId = user: config.toh.meta.sops.secrets."garage-init-key-${user}-id".path;
      initSecretKey = user: config.toh.meta.sops.secrets."garage-init-key-${user}-secret".path;

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
                      "${selfLib.garage.certs.root}/${name}"
                    else
                      builtins.replaceStrings [ "~" ] [ osUsers.${name}.home ] selfLib.garage.certs.user;
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
                      default = "${certs}/${selfLib.garage.certs.keyId}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.garage.certs.keyId}"'';
                      description = "Path to S3 key id file";
                    };
                    secretKey = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${selfLib.garage.certs.secretKey}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.garage.certs.secretKey}"'';
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
        toh.overlays.cli-s3-users = selfLib.cli.makeOverlay {
          extraRuntimeInputs = (final: [ final.s3cmd ]);
          extraTextFile = ./users.nu;
          extraTextVariables = {
            TOH_S3_USERS = builtins.toJSON cfg.users;
          };
        };

        toh.meta.sops.secrets = mergeByUser (
          {
            user,
            installSecrets,
            generateSecrets,
            keyId,
            secretKey,
            owner,
            group,
            ...
          }:
          lib.mkMerge [
            (lib.mkIf installSecrets {
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
            })
            (lib.mkIf (generateSecrets && runsGarage) {
              "garage-init-key-${user}-id" = {
                owner = selfLib.garage.user;
                group = selfLib.garage.group;
                mode = "0400";
              };
              "garage-init-key-${user}-secret" = {
                owner = selfLib.garage.user;
                group = selfLib.garage.group;
                mode = "0400";
              };
            })
          ]
        );

        toh.meta.cryl.machine = mergeByUser (
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
                ]
                ++ lib.optionals runsGarage [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-key-${user}-id";
                      to = "garage-init-key-${user}-id";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-key-${user}-secret";
                      to = "garage-init-key-${user}-secret";
                    };
                  }
                ];
              };
            }
          ])
        );

        toh.meta.cryl.cluster = mergeByUser (
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
            ...
          }:
          lib.mkIf (generateSecrets && runsGarage) [
            {
              keyId = initKeyId user;
              secretKey = initSecretKey user;
            }
          ]
        );

        toh.services.garage.init.buckets = mergeByUser (
          {
            name,
            user,
            generateSecrets,
            ...
          }:
          lib.mkIf (generateSecrets && runsGarage) [
            {
              bucket = name;
              keyId = initKeyId user;
            }
          ]
        );
      };
    };
}
