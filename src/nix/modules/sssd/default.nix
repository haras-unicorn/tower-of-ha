{
  toh.lib.nixosModules.services-sssd =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.sssd;

      ldapConfig = config.toh.meta.ldap;

      name = "sssd";

      domain = config.toh.meta.domains.service;

      usersSearchBase =
        (
          if ldapConfig.additionalUsersDn != null then
            "${ldapConfig.additionalUsersDn},${ldapConfig.baseDistinguishedName}"
          else
            ldapConfig.baseDistinguishedName
        )
        + "?subtree?(${ldapConfig.userUidNumber}=*)";

      groupsSearchBase =
        (
          if ldapConfig.additionalGroupsDn != null then
            "${ldapConfig.additionalGroupsDn},${ldapConfig.baseDistinguishedName}"
          else
            ldapConfig.baseDistinguishedName
        )
        + "?subtree?(${ldapConfig.groupGidNumber}=*)";

      bindPasswordEnv = "SSSD_LDAP_BIND_PASSWORD";
    in
    {
      options.toh.services = {
        sssd = {
          enable = lib.mkEnableOption "SSSD";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.sssd-environment = {
          description = "SSSD LDAP bind password environment file";
          wantedBy = [ "sssd.service" ];
          before = [ "sssd.service" ];
          requires = [ "toh-ldap-online.target" ];
          after = [ "toh-ldap-online.target" ];
          unitConfig.ConditionPathExists = ldapConfig.users.${name}.password;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            printf '${bindPasswordEnv}=%s\n' \
              "$(cat ${ldapConfig.users.${name}.password})" \
              > /run/sssd-environment
            chmod 600 /run/sssd-environment
          '';
        };

        services.sssd = {
          enable = true;

          settings = {
            sssd = {
              config_file_version = 2;
              services = "nss, pam, ifp";
              domains = domain;
            };

            nss = {
              filter_users = builtins.concatStringsSep "," ldapConfig.ignoredUsers;
              filter_groups = builtins.concatStringsSep "," ldapConfig.ignoredGroups;
            };

            pam = { };

            "domain/${domain}" = {
              id_provider = "ldap";
              auth_provider = "ldap";
              access_provider = "deny";
              chpass_provider = "none";
              sudo_provider = "none";

              # NOTE: this is technically a standard but might not be
              ldap_schema = "rfc2307bis";
              enumerate = true;
              cache_credentials = true;

              ldap_uri = ldapConfig.url;
              ldap_default_bind_dn = ldapConfig.users.${name}.dn;
              ldap_default_authtok = "$" + bindPasswordEnv;
            }
            // lib.optionalAttrs ldapConfig.ssl {
              ldap_tls_reqcert = "demand";
              ldap_tls_cacert = config.security.pki.caBundlePackage;
            }
            // {
              ldap_search_base = ldapConfig.baseDistinguishedName;

              ldap_user_search_base = usersSearchBase;
              ldap_user_object_class = ldapConfig.userObjectClass;
              ldap_user_name = ldapConfig.usernameAttribute;
              ldap_user_fullname = ldapConfig.displayNameAttribute;
              ldap_user_gecos = ldapConfig.displayNameAttribute;
              ldap_user_uid_number = ldapConfig.userUidNumber;
              ldap_user_gid_number = ldapConfig.userGidNumber;
              ldap_user_home_directory = ldapConfig.userHomeDirectory;
            }
            // lib.optionalAttrs (ldapConfig.memberOfAttribute != null) {
              ldap_user_member_of = ldapConfig.memberOfAttribute;
            }
            // lib.optionalAttrs (ldapConfig.userShell != null) {
              ldap_user_shell = ldapConfig.userShell;
            }
            // {
              ldap_group_search_base = groupsSearchBase;
              ldap_group_object_class = ldapConfig.groupObjectClass;
              ldap_group_gid_number = ldapConfig.groupGidNumber;
              ldap_group_name = ldapConfig.groupNameAttribute;
              ldap_group_member = ldapConfig.groupMemberAttribute;
            };
          };

          environmentFile = "/run/sssd-environment";
        };

        systemd.services.sssd = {
          wantedBy = [ "toh-ldap-online.target" ];
          requires = [ "toh-ldap-online.target" ];
          after = [ "toh-ldap-online.target" ];
        };

        toh.meta.ldap.apps.${name} = {
          user = "root";
          group = "root";
          permissions = [ tohLib.ldap.permissions.readOnly ];
        };
      };
    };
}
