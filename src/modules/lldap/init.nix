{
  toh.lib.nixosModules.services-lldap-init =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      serviceCfg = config.services.lldap;

      name = "lldap";
      owner = name;
      group = name;

      userConfigFiles = lib.imap0 (
        i: config:
        pkgs.writeText "user-config-${builtins.toString i}.json" (
          builtins.toJSON (lib.filterAttrs (_: value: value != null) config)
        )
      ) cfg.init.userConfigs;

      groupConfigFiles = lib.imap0 (
        i: config: pkgs.writeText "group-config-${builtins.toString i}.json" (builtins.toJSON config)
      ) cfg.init.groupConfigs;

      userSchemaFile = pkgs.writeText "user-schemas.json" (builtins.toJSON cfg.init.userSchemas);

      groupSchemaFile = pkgs.writeText "group-schemas.json" (builtins.toJSON cfg.init.groupSchemas);

      init = pkgs.runCommand "lldap-initialization" { } ''
        mkdir -p $out/user-configs $out/group-configs $out/user-schemas $out/group-schemas

        :> $out/user-configs/__sentinel.json
        :> $out/group-configs/__sentinel.json

        ${lib.concatMapStrings (path: "cp ${path} $out/user-configs/\n") userConfigFiles}
        ${lib.concatMapStrings (path: "cp ${path} $out/group-configs/\n") groupConfigFiles}

        cp ${userSchemaFile} $out/user-schemas/user-schemas.json
        cp ${groupSchemaFile} $out/group-schemas/group-schemas.json
      '';
    in
    {
      options.toh.services.lldap = {
        init = {
          enable = lib.mkEnableOption "LLDAP initialization" // {
            default = cfg.enable;
          };

          userSchemas = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Attribute name";
                  };
                  attributeType = lib.mkOption {
                    type = lib.types.enum [
                      "STRING"
                      "INTEGER"
                      "JPEG"
                      "DATE_TIME"
                    ];
                    description = "Attribute type";
                  };
                  isList = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is a list";
                  };
                  isEditable = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is editable";
                  };
                  isVisible = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is visible";
                  };
                };
              }
            );
            default = [ ];
            description = "LLDAP user schema attribute definitions";
          };

          groupSchemas = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Attribute name";
                  };
                  attributeType = lib.mkOption {
                    type = lib.types.enum [
                      "STRING"
                      "INTEGER"
                      "JPEG"
                      "DATE_TIME"
                    ];
                    description = "Attribute type";
                  };
                  isList = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is a list";
                  };
                  isEditable = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is editable";
                  };
                  isVisible = lib.mkOption {
                    type = lib.types.bool;
                    description = "Whether the attribute is visible";
                  };
                };
              }
            );
            default = [ ];
            description = "LLDAP group schema attribute definitions";
          };

          userConfigs = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  id = lib.mkOption {
                    type = lib.types.str;
                    description = "Username";
                  };
                  email = lib.mkOption {
                    type = lib.types.str;
                    description = "User email";
                  };
                  password = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "User password";
                  };
                  password_file = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Path to file containing the password";
                  };
                  displayName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Display name";
                  };
                  firstName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "First name";
                  };
                  lastName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Last name";
                  };
                  groups = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "List of groups the user belongs to";
                  };
                };
              }
            );
            default = [ ];
            description = "LLDAP user configs for bootstrap initialization";
          };

          groupConfigs = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Group name";
                  };
                };
              }
            );
            default = [ ];
            description = "LLDAP group configs for bootstrap initialization";
          };
        };
      };

      config = lib.mkIf cfg.init.enable {
        systemd.services.lldap-initialization = {
          description = "LLDAP initialization";
          wantedBy = [ "lldap.service" ];
          requires = [ "lldap.service" ];
          after = [ "lldap.service" ];
          path = [
            pkgs.bash
            pkgs.curl
            pkgs.jq
            pkgs.jo
          ];
          environment = {
            LLDAP_URL = "http://${serviceCfg.settings.http_host}:${builtins.toString serviceCfg.settings.http_port}";
            LLDAP_ADMIN_USERNAME = serviceCfg.settings.ldap_user_dn;
            LLDAP_ADMIN_PASSWORD_FILE = serviceCfg.environment.LLDAP_LDAP_USER_PASS_FILE;
            LLDAP_SET_PASSWORD_PATH = "${serviceCfg.package}/bin/lldap_set_password";
            USER_CONFIGS_DIR = "${init}/user-configs";
            GROUP_CONFIGS_DIR = "${init}/group-configs";
            USER_SCHEMAS_DIR = "${init}/user-schemas";
            GROUP_SCHEMAS_DIR = "${init}/group-schemas";
          };
          script = "${serviceCfg.package.src}/scripts/bootstrap.sh";
          serviceConfig = {
            User = owner;
            Group = group;
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        systemd.targets.toh-auth-ldap-initialized = {
          wantedBy = [ "lldap-initialization.service" ];
          bindsTo = [ "lldap-initialization.service" ];
          after = [ "lldap-initialization.service" ];
        };
      };
    };
}
