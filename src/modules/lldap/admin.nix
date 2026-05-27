{
  toh.lib.nixosModules.services-lldap-admin =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      name = "lldap";
      owner = name;
      group = name;
    in
    {
      imports = [
        {
          toh.overlays.cli-lldap-admin = tohLib.cli.makeOverlay {
            extraRuntimeInputs = final: [
              final.openldap
              final.lldap
              final.curl
            ];
            extraTextFile = ./admin.nu;
          };
        }
      ];

      options.toh.services = {
        lldap = {
          installAdminSecret = lib.mkEnableOption "LLDAP admin secret installation";

          generateAdminSecret = lib.mkEnableOption "LLDAP admin secret generation";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.installAdminSecret {
          services.lldap.environment = {
            LLDAP_LDAP_USER_PASS_FILE = config.sops.secrets."lldap-admin-pass".path;
          };

          toh.meta.ldap = {
            # NOTE: all users are under ou=people + base DN
            adminDistinguishedName = "uid=admin,ou=people,${config.toh.meta.ldap.baseDistinguishedName}";
            adminPassword = config.sops.secrets."lldap-admin-pass".path;
          };

          sops.secrets."lldap-admin-pass" = {
            inherit owner group;
            mode = "0400";
          };

          toh.services.lldap.createUserGroup = true;
          toh.services.lldap.generateAdminSecret = true;
        })
        (lib.mkIf cfg.generateAdminSecret {
          toh.cryl.machine = [
            {
              lldap-admin = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/lldap-admin-pass";
                      to = "lldap-admin-pass";
                    };
                  }
                ];
              };
            }
          ];

          toh.cryl.cluster = [
            {
              lldap-admin = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "lldap-admin-pass";
                    };
                  }
                ];
              };
            }
          ];
        })
      ];
    };
}
