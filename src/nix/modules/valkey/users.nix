{ selfLib, ... }:

{
  self.nixosModules.services-valkey-users.flake = true;
  self.nixosModules.services-valkey-users.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      osUsers = config.users.users;

      cfg = config.toh.services.valkey;

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.valkey.endpoint;

      valkeyUser = "valkey";
      valkeyGroup = "valkey";

      usersList = builtins.map (
        {
          name,
          value,
        }:
        value
        // {
          user = name;
          owner = value.user;
        }
      ) (lib.attrsToList cfg.users);
      servesUsers = cfg.enable && usersList != [ ];

      mergeByUser = forEachUser: lib.mkMerge (builtins.map forEachUser usersList);
    in
    {
      options.toh.services = {
        valkey = {
          users = lib.mkOption {
            default = { };
            description = "Valkey ACL users";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, config, ... }:
                let
                  certs =
                    if !builtins.elem name (builtins.attrNames osUsers) || osUsers.${name}.home == "/var/empty" then
                      "${selfLib.valkey.certs.root}/${name}"
                    else
                      builtins.replaceStrings [ "~" ] [ osUsers.${name}.home ] selfLib.valkey.certs.user;
                in
                {
                  options = {
                    active = lib.mkEnableOption "User ${name} active" // {
                      default = true;
                    };

                    installSecrets = lib.mkEnableOption "valkey user secrets installation";

                    generateSecrets = lib.mkEnableOption "valkey user secrets generation";

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
                    prefix = lib.mkOption {
                      type = lib.types.oneOf [
                        lib.types.str
                        (lib.types.enum [
                          "all"
                          "none"
                        ])
                      ];
                      default = "${name}:";
                      description = "Key prefix for the ACL user";
                    };
                    channels = lib.mkOption {
                      type = lib.types.oneOf [
                        lib.types.str
                        (lib.types.enum [
                          "all"
                          "none"
                        ])
                      ];
                      default = config.prefix;
                      defaultText = lib.literalExpression "prefix";
                      description = "Channel prefix for the ACL user";
                    };
                    database = lib.mkOption {
                      type = lib.types.oneOf [
                        lib.types.ints.unsigned
                        (lib.types.enum [
                          "all"
                          "none"
                        ])
                      ];
                      default = null;
                      description = "Database for ACL user";
                    };
                    permissions = lib.mkOption {
                      type = lib.types.listOf (lib.types.enum (builtins.attrValues selfLib.kv.permissions));
                      default = null;
                      description = "Permissions for ACL user";
                    };
                    denied = lib.mkOption {
                      type = lib.types.listOf (
                        lib.types.enum (
                          builtins.attrValues (
                            builtins.removeAttrs selfLib.kv.permissions [
                              "all"
                              "none"
                              "health"
                            ]
                          )
                        )
                      );
                      default = [ selfLib.kv.permissions.dangerous ];
                      description = ''
                        Command categories denied to the ACL user after its
                        permissions; the default keeps it from flushing every
                        key, changing the config or rewriting users
                      '';
                    };
                    password = lib.mkOption {
                      type = lib.types.nullOr lib.types.path;
                      default = "${certs}/${selfLib.valkey.password}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.valkey.password}"'';
                      description = "Path to user valkey password file";
                    };
                    url = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${selfLib.valkey.url}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.valkey.url}"'';
                      description = "Path to user valkey URL file";
                    };
                    ca = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${selfLib.valkey.certs.ca}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.valkey.certs.ca}"'';
                      description = "Path to user valkey root certificate";
                    };
                    crt = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${selfLib.valkey.certs.crt}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.valkey.certs.crt}"'';
                      description = "Path to user valkey certificate";
                    };
                    key = lib.mkOption {
                      type = lib.types.path;
                      default = "${certs}/${selfLib.valkey.certs.key}";
                      defaultText = lib.literalExpression ''"${certs}/${selfLib.valkey.certs.key}"'';
                      description = "Path to user valkey key";
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
        toh.overlays.cli-valkey-users = selfLib.cli.makeOverlay {
          extraRuntimeInputs = (final: [ final.valkey ]);
          extraTextFile = ./users.nu;
          extraTextVariables = {
            TOH_VALKEY_USERS = builtins.toJSON cfg.users;
          };
        };

        toh.meta.sops.secrets = lib.mkMerge [
          (lib.mkIf servesUsers {
            "valkey-acl" = {
              owner = valkeyUser;
              group = valkeyGroup;
              mode = "0400";
            };
          })
          (mergeByUser (
            {
              user,
              installSecrets,
              url,
              ca,
              crt,
              key,
              password,
              owner,
              group,
              ...
            }:
            lib.mkIf installSecrets {
              "valkey-${user}-ca" = {
                inherit owner group;
                key = "openssl-ca-public";
                path = ca;
                public = true;
              };
              "valkey-${user}-public" = {
                inherit owner group;
                path = crt;
                public = true;
              };
              "valkey-${user}-private" = {
                inherit owner group;
                path = key;
                mode = "0400";
              };
              "valkey-${user}-url" = {
                inherit owner group;
                path = url;
                mode = "0400";
              };
              "valkey-${user}-pass" = {
                inherit owner group;
                path = lib.mkIf (password != null) password;
                mode = "0400";
              };
            }
          ))
        ];

        toh.meta.cryl.machine = lib.mkMerge [
          (lib.mkIf servesUsers (
            lib.mkAfter [
              {
                "valkey-acl" = {
                  generations = [
                    {
                      generator = "mustache";
                      arguments = {
                        name = "valkey-acl";
                        renew = true;
                        listing = {
                          type = "map";
                          value = builtins.listToAttrs (
                            builtins.concatMap (
                              { user, generateSecrets, ... }:
                              lib.optional generateSecrets {
                                name = "VALKEY_${lib.toUpper user}_PASS";
                                value = "cluster/valkey-${user}-pass";
                              }
                            ) usersList
                          );
                        };
                        template = builtins.concatStringsSep "\n" (
                          builtins.map (
                            {
                              user,
                              active,
                              password,
                              prefix,
                              channels,
                              database,
                              permissions,
                              denied,
                              generateSecrets,
                              ...
                            }:
                            let
                              activePart = if active then "on" else "off";
                              passwordPart = if password == null then "nopass" else ">{{{VALKEY_${lib.toUpper user}_PASS}}}";
                              keysPart =
                                if prefix == "all" then
                                  "allkeys"
                                else if prefix == "none" then
                                  "resetkeys"
                                else
                                  "~${prefix}*";
                              channelsPart =
                                if channels == "all" then
                                  "allchannels"
                                else if channels == "none" then
                                  "resetchannels"
                                else
                                  "&${channels}*";
                              permissionPart = builtins.concatStringsSep " " (
                                builtins.map (
                                  permission:
                                  if permission == "all" then
                                    "allcommands"
                                  else if permission == "health" then
                                    "+ping +info"
                                  else if permission == "none" then
                                    "nocommands"
                                  else
                                    "+@${permission}"
                                ) permissions
                              );
                              deniedPart = builtins.concatStringsSep " " (builtins.map (category: "-@${category}") denied);
                              databasePart =
                                if database == "all" then
                                  "alldbs"
                                else if database == "none" then
                                  "resetdbs"
                                else
                                  "db=${builtins.toString database}";
                            in
                            lib.optionalString generateSecrets (
                              builtins.concatStringsSep " " (
                                builtins.filter (part: part != "") [
                                  "user"
                                  user
                                  activePart
                                  passwordPart
                                  keysPart
                                  channelsPart
                                  databasePart
                                  permissionPart
                                  deniedPart
                                ]
                              )
                            )
                          ) usersList
                        );
                      };
                    }
                  ];
                };
              }
            ]
          ))
          (mergeByUser (
            {
              user,
              installSecrets,
              ca,
              crt,
              key,
              ...
            }:
            lib.mkIf installSecrets [
              {
                "valkey-${user}" = {
                  generations = [
                    {
                      generator = "copy";
                      arguments = {
                        renew = true;
                        from = "cluster/valkey-${user}-pass";
                        to = "valkey-${user}-pass";
                      };
                    }
                    {
                      generator = "tls-leaf";
                      arguments = {
                        common_name = user;
                        organization = "ToH";
                        sans = [
                          proxyAttrs.host
                          config.toh.meta.network.ip
                          "localhost"
                          "127.0.0.1"
                        ];
                        config = "valkey-${user}-cert-config";
                        request_config = "valkey-${user}-cert-request-config";
                        private = "valkey-${user}-private";
                        request = "valkey-${user}-cert-request";
                        ca_private = "cluster/openssl-ca-private";
                        ca_public = "cluster/openssl-ca-public";
                        serial = "cluster/openssl-ca-serial";
                        public = "valkey-${user}-public";
                        renew = true;
                      };
                    }
                    {
                      generator = "mustache";
                      arguments = {
                        name = "valkey-${user}-url";
                        renew = true;
                        listing = {
                          type = "map";
                          value = {
                            VALKEY_USER_PASS = "cluster/valkey-${user}-pass";
                          };
                        };
                        template = selfLib.url.makeUrl {
                          protocol = "rediss";
                          inherit (proxyAttrs) host port;
                          inherit user;
                          password = "{{{VALKEY_USER_PASS}}}";
                          parameters = {
                            ssl = "True";
                            ssl_cert_reqs = "required";
                            ssl_ca_path = ca;
                            ssl_certfile = crt;
                            ssl_keyfile = key;
                          };
                        };
                      };
                    }
                  ];
                };
              }
            ]
          ))
        ];

        toh.meta.cryl.cluster = mergeByUser (
          { user, generateSecrets, ... }:
          lib.mkIf generateSecrets [
            {
              "valkey-${user}" = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "valkey-${user}-pass";
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = user;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "valkey-${user}-cert-config";
                      request_config = "valkey-${user}-cert-request-config";
                      private = "valkey-${user}-private";
                      request = "valkey-${user}-cert-request";
                      ca_private = "openssl-ca-private";
                      ca_public = "openssl-ca-public";
                      serial = "openssl-ca-serial";
                      public = "valkey-${user}-public";
                      renew = true;
                    };
                  }
                ];
              };
            }
          ]
        );

        toh.services.valkey.createUserGroup = mergeByUser (
          { installSecrets, ... }: lib.mkIf installSecrets true
        );

        toh.pki.generateCa = mergeByUser ({ generateSecrets, ... }: lib.mkIf generateSecrets true);
      };
    };
}
