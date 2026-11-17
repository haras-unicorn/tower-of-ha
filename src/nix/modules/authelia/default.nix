# TODO: ntp from reverse proxied ntp server
# - need traefik for udp revere proxy and abstracting away chrony

{
  toh.lib.nixosModules.services-authelia =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.authelia;
      instanceCfg = config.services.authelia.instances.authelia;

      format = pkgs.formats.yaml { };

      anyMachines = tohLib.anyServiceMachines "authelia";

      proxyUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.authelia.endpoint { };
      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.authelia.endpoint;

      port = 9091;

      name = "authelia";
      owner = name;
      group = name;

      ldapConfig = config.toh.meta.ldap;

      dbConfig = config.toh.meta.database;
      dbName =
        if dbConfig.protocol == "postgresql" then
          "postgres"
        else if dbConfig.protocol == "mysql" then
          "mysql"
        else if dbConfig.protocol == "sqlite" then
          "local"
        else
          builtins.throw "Unsupported Authelia database";
      dbInstance = config.toh.meta.database.instances.${name};

      kvConfig = config.toh.meta.kv;
      kvName = if kvConfig.protocol == "redis" then "redis" else "redis";
      kvInstance = config.toh.meta.kv.instances.${name};

      emailConfig = config.toh.meta.email;
      emailInstance = config.toh.meta.email.emails.${name};

      trust = "/run/authelia/trust";
    in
    {
      options.toh.services = {
        authelia = {
          enable = lib.mkEnableOption "Authelia";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.oidc = {
            issuer = proxyUrl;
            baseUrl = proxyUrl;
          };
        })
        (lib.mkIf cfg.enable {
          environment.systemPackages = [
            instanceCfg.package
          ];

          services.authelia.instances.authelia = {
            enable = true;
            user = owner;
            group = group;

            # NOTE: https://www.authelia.com/configuration/identity-providers/openid-connect/provider/#key
            settingsFiles = [
              (pkgs.writeText "authelia-config-jwks.yaml" ''
                identity_providers:
                  oidc:
                    jwks:
                      - algorithm: RS256
                        key: |
                {{ secret "${config.toh.meta.sops.secrets."authelia-jwks-rsa-key".path}" | indent 10 }}
                        certificate_chain: |
                {{ secret "${
                  config.toh.meta.sops.secrets."authelia-jwks-rsa-certificate-chain".path
                }" | indent 10 }}
                      - algorithm: ES256
                        key: |
                {{ secret "${config.toh.meta.sops.secrets."authelia-jwks-key".path}" | indent 10 }}
                        certificate_chain: |
                {{ secret "${config.toh.meta.sops.secrets."authelia-jwks-certificate-chain".path}" | indent 10 }}
              '')
              (pkgs.writeText "authelia-config-database.yaml" ''
                storage:
                  ${dbName}:
                    address: 'tcp://${dbConfig.host}:${builtins.toString dbConfig.port}'
                    database: '${name}'
                    username: '${name}'
                    password: {{ secret "${dbInstance.password}" }}
                    tls:
                      private_key: |
                {{ secret "${dbInstance.ssl.key}" | indent 8 }}
                      certificate_chain: |
                {{ secret "${dbInstance.ssl.crt}" | indent 8 }}
              '')
              (pkgs.writeText "authelia-config-session.yaml" ''
                session:
                  ${kvName}:
                    host: '${kvConfig.host}'
                    port: ${builtins.toString kvConfig.port}
                    username: '${name}'
                    password: {{ secret "${kvInstance.password}" }}
                    database_index: ${builtins.toString kvInstance.database}
                    tls:
                      private_key: |
                {{ secret "${kvInstance.ssl.key}" | indent 8 }}
                      certificate_chain: |
                {{ secret "${kvInstance.ssl.crt}" | indent 8 }}
              '')
              (pkgs.writeText "authelia-config-notifications.yaml" ''
                notifier:
                  disable_startup_check: true
                  smtp:
                    address: "smtp://${emailConfig.domain}:25"
                    username: '${name}'
                    password: {{ secret "${emailInstance.password}" }}
                    sender: 'Auth <${emailInstance.address}>'
                    startup_check_address: '${emailConfig.admin}'
              '')
            ];

            settings = {
              certificates_directory = trust;

              theme = "auto";
              default_2fa_method = "totp";

              server = {
                address = "tcp://${config.toh.meta.network.ip}:${builtins.toString port}";
              };

              log = {
                level = "info";
                format = "text";
              };

              authentication_backend = {
                ldap = {
                  implementation = "custom";
                  address = ldapConfig.url;
                  base_dn = ldapConfig.baseDistinguishedName;
                  user = ldapConfig.users.authelia.dn;
                  users_filter =
                    let
                      usernameFilter = lib.optionalString (
                        ldapConfig.usernameAttribute != null
                      ) "({username_attribute}={input})";
                      mailFilter = lib.optionalString (ldapConfig.mailAttribute != null) "({mail_attribute}={input})";
                    in
                    "(&(|${usernameFilter}${mailFilter})(objectClass=${ldapConfig.userObjectClass}))";
                  groups_filter =
                    let
                      groupMemberFilter = lib.optionalString (
                        ldapConfig.groupMemberAttribute != null
                      ) "(${ldapConfig.groupMemberAttribute}={dn})";
                    in
                    "(&(|${groupMemberFilter})(objectClass=${ldapConfig.groupObjectClass}))";
                }
                // lib.optionalAttrs (ldapConfig.additionalUsersDn != null) {
                  additional_users_dn = ldapConfig.additionalUsersDn;
                }
                // lib.optionalAttrs (ldapConfig.additionalGroupsDn != null) {
                  additional_groups_dn = ldapConfig.additionalGroupsDn;
                }
                // {
                  attributes = lib.filterAttrs (_: value: value != null) {
                    username = ldapConfig.usernameAttribute;
                    display_name = ldapConfig.displayNameAttribute;
                    mail = ldapConfig.mailAttribute;
                    member_of = ldapConfig.memberOfAttribute;
                    group_name = ldapConfig.groupNameAttribute;
                  };
                };
              };

              session = {
                # NOTE: can't be a TLD
                cookies = [
                  {
                    domain = config.toh.meta.domains.service;
                    authelia_url = proxyUrl;
                  }
                ];
              };

              access_control = {
                default_policy = "deny";
                rules = [
                  {
                    domain = config.toh.meta.domains.topLevel;
                    policy = "one_factor";
                  }
                ];
              };
            };

            secrets.manual = true;

            environmentVariables = {
              # NOTE: https://www.authelia.com/configuration/identity-providers/openid-connect/provider/#key
              X_AUTHELIA_CONFIG_FILTERS = "template";
              AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = ldapConfig.users.authelia.password;
              AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE =
                config.toh.meta.sops.secrets."authelia-jwt-secret".path;
              AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE =
                config.toh.meta.sops.secrets."authelia-storage-encryption-key".path;
              AUTHELIA_SESSION_SECRET_FILE = config.toh.meta.sops.secrets."authelia-session-secret".path;
              AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE =
                config.toh.meta.sops.secrets."authelia-oidc-hmac-secret".path;
            };
          };

          users.groups.${group} = { };
          users.users.${owner} = {
            group = group;
            isSystemUser = true;
          };

          systemd.tmpfiles.rules = [
            "d ${trust} 0755 authelia authelia -"
          ];

          systemd.services."authelia-authelia" = {
            preStart = ''
              ln -sf "${dbInstance.ssl.ca}" "${trust}/storage.crt"
            '';
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = lib.mkForce owner;
              Group = lib.mkForce group;
            };
            wantedBy = [
              "toh-database-online.target"
              "toh-ldap-online.target"
            ];
            requires = [
              "toh-database-online.target"
              "toh-ldap-online.target"
            ];
            after = [
              "toh-database-online.target"
              "toh-ldap-online.target"
            ];
          };

          systemd.targets.toh-oidc-online = {
            wantedBy = [ "authelia-authelia.service" ];
            bindsTo = [ "authelia-authelia.service" ];
            after = [ "authelia-authelia.service" ];
          };

          networking.firewall.allowedTCPPorts = [ port ];

          toh.meta.sops.secrets."authelia-jwt-secret" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-session-secret" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-storage-encryption-key" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-oidc-hmac-secret" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-jwks-key" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-jwks-certificate-chain" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-jwks-rsa-key" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."authelia-jwks-rsa-certificate-chain" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.cryl.machine = [
            {
              authelia = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-jwt-secret";
                      to = "authelia-jwt-secret";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-session-secret";
                      to = "authelia-session-secret";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-storage-encryption-key";
                      to = "authelia-storage-encryption-key";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-oidc-hmac-secret";
                      to = "authelia-oidc-hmac-secret";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-jwks-key";
                      to = "authelia-jwks-key";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-jwks-certificate-chain";
                      to = "authelia-jwks-certificate-chain";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-jwks-rsa-key";
                      to = "authelia-jwks-rsa-key";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-jwks-rsa-certificate-chain";
                      to = "authelia-jwks-rsa-certificate-chain";
                    };
                  }
                ];
              };
            }
          ];

          toh.meta.cryl.cluster = [
            {
              authelia = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "authelia-jwt-secret";
                      length = 64;
                    };
                  }
                  {
                    generator = "key";
                    arguments = {
                      name = "authelia-session-secret";
                      length = 64;
                    };
                  }
                  {
                    generator = "key";
                    arguments = {
                      name = "authelia-storage-encryption-key";
                      length = 64;
                    };
                  }
                  {
                    generator = "key";
                    arguments = {
                      name = "authelia-oidc-hmac-secret";
                      length = 64;
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = "authelia";
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "authelia-jwks-cert-config";
                      request_config = "authelia-jwks-cert-request-config";
                      private = "authelia-jwks-private";
                      request = "authelia-jwks-cert-request";
                      ca_private = "openssl-ca-private";
                      ca_public = "openssl-ca-public";
                      serial = "openssl-ca-serial";
                      public = "authelia-jwks-public";
                      renew = true;
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "authelia-jwks-private";
                      to = "authelia-jwks-key";
                    };
                  }
                  {
                    generator = "script";
                    arguments = {
                      name = "authelia-jwks-certificate-chain-script";
                      renew = true;
                      text = ''
                        (echo $"(open --raw authelia-jwks-public)(open --raw openssl-ca-public)"
                          | save -f authelia-jwks-certificate-chain)
                      '';
                    };
                  }
                  {
                    generator = "tls-rsa-root";
                    arguments = {
                      common_name = "authelia";
                      organization = "ToH";
                      config = "authelia-jwks-rsa-config";
                      private = "authelia-jwks-rsa-private";
                      public = "authelia-jwks-rsa-public";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "authelia-jwks-rsa-private";
                      to = "authelia-jwks-rsa-key";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "authelia-jwks-rsa-public";
                      to = "authelia-jwks-rsa-certificate-chain";
                    };
                  }
                ];
              };
            }
          ];

          toh.meta.services.authelia = {
            endpoint.http.port = port;
            health.endpoint.http = {
              inherit port;
              path = "/api/health";
            };
          };

          toh.meta.ldap.apps.${name} = {
            user = owner;
            group = group;
            permissions = [ tohLib.ldap.permissions.passwordChange ];
          };

          toh.meta.email.apps.${name} = {
            user = owner;
            group = group;
          };

          toh.meta.kv.apps.${name} = {
            user = owner;
            group = group;
            database = port;
            permissions = [
              tohLib.kv.permissions.read
              tohLib.kv.permissions.write
              tohLib.kv.permissions.connection
              tohLib.kv.permissions.keyspace
            ];
          };

          systemd.services.authelia-authelia-storage-migration =
            let
              config = builtins.concatStringsSep "," (
                [ (format.generate "authelia-config.yml" instanceCfg.settings) ] ++ instanceCfg.settingsFiles
              );
            in
            {
              description = "Authelia authentication and authorization server storage migration";
              path = [ instanceCfg.package ];
              environment = instanceCfg.environmentVariables;
              preStart = ''
                authelia validate-config --config=${config}
                ln -sf "${dbInstance.ssl.ca}" "${trust}/storage.crt"
              '';
              script = ''
                authelia storage migrate up --config=${config}
              '';
              serviceConfig = {
                User = owner;
                Group = group;
                Type = "oneshot";
              };
            };

          toh.meta.database.apps.${name} = {
            user = owner;
            group = group;
            init.systemd.unit = "authelia-authelia-storage-migration.service";
          };
        })
      ];
    };
}
