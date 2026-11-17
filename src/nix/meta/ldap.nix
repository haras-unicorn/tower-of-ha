{
  toh.lib.nixosModules.meta-ldap =
    { lib, tohLib, ... }:
    {
      options.toh.meta = {
        ldap = {
          baseDistinguishedName = lib.mkOption {
            type = lib.types.str;
            description = "LDAP base distinguished name";
          };
          adminDistinguishedName = lib.mkOption {
            type = lib.types.str;
            description = "LDAP admin user distinguished name";
          };
          adminPassword = lib.mkOption {
            type = lib.types.str;
            description = "Admin password secret";
          };
          ssl = lib.mkOption {
            type = lib.types.bool;
            description = "Whether to use LDAPS";
          };
          host = lib.mkOption {
            type = lib.types.str;
            description = "LDAP server host";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = "LDAP server port";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "LDAP connection URL for clients";
          };
          additionalUsersDn = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Additional users DN";
          };
          additionalGroupsDn = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Additional groups DN";
          };
          usernameAttribute = lib.mkOption {
            type = lib.types.str;
            description = "LDAP username attribute";
          };
          displayNameAttribute = lib.mkOption {
            type = lib.types.str;
            description = "LDAP display name attribute";
          };
          mailAttribute = lib.mkOption {
            type = lib.types.str;
            description = "LDAP mail attribute";
          };
          memberOfAttribute = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "LDAP memberOf attribute";
          };
          groupNameAttribute = lib.mkOption {
            type = lib.types.str;
            description = "LDAP group name attribute";
          };
          userObjectClass = lib.mkOption {
            type = lib.types.str;
            description = "LDAP user object class";
          };
          groupObjectClass = lib.mkOption {
            type = lib.types.str;
            description = "LDAP group object class";
          };
          groupMemberAttribute = lib.mkOption {
            type = lib.types.str;
            description = "LDAP group member attribute";
          };
          idMapping = lib.mkOption {
            type = lib.types.bool;
            description = "Whether to generate UIDs/GIDs for LDAP entries";
          };
          ignoredUsers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Users to hide from NSS";
          };
          ignoredGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Groups to hide from NSS";
          };
          userUidNumber = lib.mkOption {
            type = lib.types.str;
            description = "LDAP attribute for the user's UID number";
          };
          userGidNumber = lib.mkOption {
            type = lib.types.str;
            description = "LDAP attribute for the user's GID number";
          };
          userHomeDirectory = lib.mkOption {
            type = lib.types.str;
            description = "LDAP attribute for the user's home directory";
          };
          userShell = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "LDAP attribute for the user's shell";
          };
          groupGidNumber = lib.mkOption {
            type = lib.types.str;
            description = "LDAP attribute for the group's GID number";
          };
          apps = lib.mkOption {
            description = "LDAP applications to create users for";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "LDAP password owner linux user";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "LDAP password owner linux group";
                    };
                    permissions = lib.mkOption {
                      type = lib.types.listOf (lib.types.enum (builtins.attrValues tohLib.ldap.permissions));
                      description = "LDAP permissions for the user";
                    };
                  };
                }
              )
            );
          };
          users = lib.mkOption {
            description = "LDAP users for applications";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  dn = lib.mkOption {
                    type = lib.types.str;
                    description = "Full distinguished name of the LDAP user";
                  };
                  password = lib.mkOption {
                    type = lib.types.path;
                    description = "Path to LDAP user password";
                  };
                };
              }
            );
          };
        };
      };
    };
}
