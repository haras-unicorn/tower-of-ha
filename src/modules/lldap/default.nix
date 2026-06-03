# TODO: app emails via actual email meta

{
  toh.lib.nixosModules.services-lldap =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      anyMachines = tohLib.anyServiceMachines "lldap";

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.ldap.endpoint;

      proxyUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.ldap.endpoint { };

      format = pkgs.formats.toml { };

      httpPort = 17170;
      ldapPort = 3890;

      name = "lldap";
      owner = name;
      group = name;

      baseDistinguishedName = builtins.concatStringsSep "," (
        builtins.map (component: "dc=${component}") (lib.splitString "." config.toh.meta.domains.topLevel)
      );

      adminName = "admin";
    in
    {
      options.toh.services = {
        lldap = {
          enable = lib.mkEnableOption "LLDAP";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.ldap = {
            host = proxyAttrs.host;
            port = proxyAttrs.port;
            ssl = proxyAttrs.protocol == "ldaps";
            url = proxyUrl;

            baseDistinguishedName = baseDistinguishedName;

            additionalUsersDn = "ou=people";
            usersFilter = "(&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))";
            userObjectClass = "posixAccount";
            usernameAttribute = "uid";
            displayNameAttribute = "cn";
            mailAttribute = "mail";
            memberOfAttribute = "memberOf";
            userUidNumber = "uidNumber";
            userGidNumber = "gidNumber";
            userHomeDirectory = "homeDirectory";
            userShell = "unixShell";
            ignoredUsers = [
              "admin"
              "root"
            ];

            additionalGroupsDn = "ou=groups";
            groupsFilter = "(&(member={dn})(objectClass=groupOfUniqueNames))";
            groupObjectClass = "groupOfUniqueNames";
            groupNameAttribute = "cn";
            groupGidNumber = "gidNumber";
            groupMemberAttribute = "uniqueMember";
            idMapping = false;
            ignoredGroups = [
              "admin"
              "root"
            ];
          };
        })
        (lib.mkIf cfg.enable {
          environment.systemPackages = [
            config.services.lldap.package
            pkgs.openldap
          ];

          services.lldap.enable = true;

          services.lldap.settings = {
            ldap_host = config.toh.meta.network.ip;
            ldap_port = ldapPort;
            ldap_base_dn = config.toh.meta.ldap.baseDistinguishedName;
            # NOTE: it says DN but LLDAP actually expects just a username
            ldap_user_dn = adminName;
            # TODO: use dovecot/postfix
            ldap_user_email = "admin@email.${config.toh.meta.domains.service}";
            http_host = config.toh.meta.network.ip;
            http_port = httpPort;
            http_url = proxyUrl;
            force_ldap_user_pass_reset = "always";
          };

          services.lldap.environment = {
            LLDAP_KEY_SEED_FILE = config.sops.secrets."lldap-key-seed".path;
            LLDAP_JWT_SECRET_FILE = config.sops.secrets."lldap-jwt-secret".path;
            LLDAP_DATABASE_URL_FILE = config.toh.meta.database.instances.lldap.url;
            RUST_LOG = "warn";
          };

          systemd.services.lldap = {
            wantedBy = [ "toh-database-initialized.target" ];
            requires = [ "toh-database-initialized.target" ];
            after = [ "toh-database-initialized.target" ];
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = lib.mkForce owner;
              Group = lib.mkForce group;
            };
          };

          systemd.targets.toh-auth-ldap-initialized = {
            wantedBy = [ "lldap.service" ];
            bindsTo = [ "lldap.service" ];
            after = [ "lldap.service" ];
          };

          networking.firewall.allowedTCPPorts = [
            httpPort
            ldapPort
          ];

          toh.meta.services.lldap = {
            endpoint.http.port = httpPort;
            health.endpoint.http = {
              port = httpPort;
              path = "/health";
            };
          };

          toh.meta.services.ldap = {
            endpoint.tcp = {
              port = ldapPort;
              layer7Protocol = "ldaps";
            };
            health.endpoint.http = {
              port = httpPort;
              path = "/health";
            };
          };

          sops.secrets."lldap-jwt-secret" = {
            inherit owner group;
            mode = "0400";
          };
          sops.secrets."lldap-key-seed" = {
            inherit owner group;
            mode = "0400";
          };

          toh.cryl.machine = [
            {
              lldap = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/lldap-jwt-secret";
                      to = "lldap-jwt-secret";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/lldap-key-seed";
                      to = "lldap-key-seed";
                    };
                  }
                ];
              };
            }
          ];

          toh.cryl.cluster = [
            {
              lldap = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "lldap-jwt-secret";
                    };
                  }
                  {
                    generator = "key";
                    arguments = {
                      name = "lldap-key-seed";
                    };
                  }
                ];
              };
            }
          ];

          systemd.services.lldap-create-schema = {
            description = "Lightweight LDAP server (lldap) database schema creation";
            path = [ config.services.lldap.package ];
            environment = config.services.lldap.environment;
            script = ''
              exec lldap create_schema \
                --config-file ${format.generate "lldap_config.toml" config.services.lldap.settings}
            '';
            serviceConfig = {
              StateDirectory = "lldap";
              StateDirectoryMode = "0750";
              WorkingDirectory = "%S/lldap";
              UMask = "0027";
              User = owner;
              Group = group;
              Type = "oneshot";
            };
          };

          toh.meta.database.apps.${name} = {
            user = owner;
            group = group;
            init.systemd.unit = "lldap-create-schema.service";
          };

          toh.services.lldap.installAdminSecret = true;

          toh.services.lldap.init = {
            enable = true;

            userSchemas = [
              {
                name = "uidNumber";
                attributeType = "INTEGER";
                isList = false;
                isEditable = true;
                isVisible = true;
              }
              {
                name = "gidNumber";
                attributeType = "INTEGER";
                isList = false;
                isEditable = true;
                isVisible = true;
              }
              {
                name = "homeDirectory";
                attributeType = "STRING";
                isList = false;
                isEditable = true;
                isVisible = true;
              }
              {
                name = "unixShell";
                attributeType = "STRING";
                isList = false;
                isEditable = true;
                isVisible = true;
              }
            ];

            groupSchemas = [
              {
                name = "gidNumber";
                attributeType = "INTEGER";
                isList = false;
                isEditable = true;
                isVisible = true;
              }
            ];
          };
        })
      ];
    };
}
