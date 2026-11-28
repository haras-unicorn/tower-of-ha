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

      initKeyId = name: config.toh.meta.sops.secrets."garage-init-key-${name}-id".path;
      initSecretKey = name: config.toh.meta.sops.secrets."garage-init-key-${name}-secret".path;

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
            name,
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
              "garage-key-${name}-id" = {
                inherit owner group;
                path = keyId;
                mode = "0400";
              };
              "garage-key-${name}-secret" = {
                inherit owner group;
                path = secretKey;
                mode = "0400";
              };
            })
            (lib.mkIf (generateSecrets && runsGarage) {
              "garage-init-key-${name}-id" = {
                owner = selfLib.garage.user;
                group = selfLib.garage.group;
                mode = "0400";
              };
              "garage-init-key-${name}-secret" = {
                owner = selfLib.garage.user;
                group = selfLib.garage.group;
                mode = "0400";
              };
            })
          ]
        );

        toh.meta.cryl.machine = mergeByUser (
          {
            name,
            installSecrets,
            generateSecrets,
            ...
          }:
          let
            initsUser = generateSecrets && runsGarage;
          in
          lib.mkIf (installSecrets || initsUser) ([
            {
              "garage-key-${name}" = {
                generations =
                  lib.optionals installSecrets [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/garage-key-${name}-id";
                        to = "garage-key-${name}-id";
                      };
                    }
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/garage-key-${name}-secret";
                        to = "garage-key-${name}-secret";
                      };
                    }
                  ]
                  ++ lib.optionals initsUser [
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/garage-key-${name}-id";
                        to = "garage-init-key-${name}-id";
                      };
                    }
                    {
                      generator = "copy";
                      arguments = {
                        from = "cluster/garage-key-${name}-secret";
                        to = "garage-init-key-${name}-secret";
                      };
                    }
                  ];
              };
            }
          ])
        );

        toh.meta.cryl.cluster = mergeByUser (
          { name, generateSecrets, ... }:
          lib.mkIf generateSecrets [
            {
              "garage-key-${name}" = {
                generations = [
                  {
                    generator = "script";
                    arguments = {
                      name = "garage-key-${name}-id-script";
                      renew = true;
                      text = ''$"GK(openssl rand -hex 12)" | save -f garage-key-${name}-id'';
                    };
                  }
                  {
                    generator = "script";
                    arguments = {
                      name = "garage-key-${name}-secret-script";
                      renew = true;
                      text = ''$"(openssl rand -hex 32)" | save -f garage-key-${name}-secret'';
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
            name,
            generateSecrets,
            ...
          }:
          lib.mkIf (generateSecrets && runsGarage) [
            {
              keyId = initKeyId name;
              secretKey = initSecretKey name;
            }
          ]
        );

        toh.services.garage.init.buckets = mergeByUser (
          {
            name,
            generateSecrets,
            ...
          }:
          lib.mkIf (generateSecrets && runsGarage) [
            {
              bucket = name;
              keyId = initKeyId name;
            }
          ]
        );
      };
    };
}
