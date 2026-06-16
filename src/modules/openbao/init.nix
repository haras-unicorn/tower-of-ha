{
  toh.lib.nixosModules.services-openbao-init =
    {
      config,
      lib,
      pkgs,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.openbao;

      user = tohLib.openbao.user;
      group = tohLib.openbao.group;

      mountKey = config.toh.meta.secrets.keys.mount;
      machinesKey = config.toh.meta.secrets.keys.machines;
      rootKey = config.toh.meta.secrets.keys.root;

      machineAclTemplate = pkgs.writeText "openbao-machine-acl-template" ''
        path "${mountKey}/data/${machinesKey}/{{identity.entity.aliases.<USERPASS_ACCESSOR>.name}}" {
          capabilities = ["create", "update", "patch", "read", "delete"]
        }

        path "${mountKey}/metadata/${machinesKey}/{{identity.entity.aliases.<USERPASS_ACCESSOR>.name}}" {
          capabilities = ["list"]
        }

        path "auth/token/create" {
          capabilities = ["sudo", "create", "read", "update", "delete"]
        }
      '';

      adminAcl = pkgs.writeText "openbao-admin-acl" ''
        path "identity/*"
        {
          capabilities = ["create", "read", "update", "delete", "list", "sudo"]
        }

        path "auth/*"
        {
          capabilities = ["create", "read", "update", "delete", "list", "sudo"]
        }

        path "sys/policies/acl"
        {
          capabilities = ["read","list"]
        }

        path "sys/policies/acl/*"
        {
          capabilities = ["create", "read", "update", "delete", "list", "sudo"]
        }

        path "${mountKey}/*"
        {
          capabilities = ["create", "read", "update", "delete", "list", "sudo"]
        }
      '';
    in
    {
      options.toh.services = {
        openbao = {
          init = {
            enable = lib.mkEnableOption "Openbao initialization" // {
              default = cfg.enable;
            };
          };
        };
      };

      config = lib.mkIf cfg.init.enable {
        toh.overlays = tohLib.cli.makeOverlays {
          name = "openbao-init";
          runtimeInputs = pkgs: [
            pkgs.openbao
            pkgs.sops
          ];
          textFile = ./init.nu;
          textVariables = {
            TOH_OPENBAO_KEYS_MOUNT = mountKey;
            TOH_OPENBAO_MACHINES_KEY = machinesKey;
            TOH_OPENBAO_ROOT_KEY = rootKey;
            TOH_OPENBAO_AGE_KEY_PATH = config.toh.meta.sops.secrets.${config.toh.meta.secrets.keys.age}.path;
            TOH_OPENBAO_ROOT_FAIL_PATH = config.toh.meta.secrets.files.root;
            TOH_OPENBAO_SOPS_FILE = config.toh.meta.secrets.files.sops;
            TOH_OPENBAO_MACHINE_ACL_TEMPLATE_FILE = builtins.toString machineAclTemplate;
            TOH_OPENBAO_ADMIN_ACL_FILE = builtins.toString adminAcl;
            TOH_OPENBAO_ADDRESS =
              tohLib.services.endpoint.toUrl config.toh.meta.proxies.openbao-init.endpoint
                { };
            TOH_OPENBAO_MACHINE_NAME = config.toh.meta.machine.name;
            TOH_OPENBAO_MACHINE_PASSWORDS = builtins.toJSON (
              builtins.listToAttrs (
                builtins.map (machine: {
                  name = machine.name;
                  value = builtins.toString config.toh.meta.sops.secrets."openbao-machine-${machine.name}-pass".path;
                }) config.toh.meta.cluster.machinea
              )
            );
            TOH_OPENBAO_ADMIN_PASSWORD = config.toh.meta.sops.secrets."openbao-admin-pass".path;
          };
        };

        systemd.services.openbao-initialization = {
          description = "ToH OpenBao initialization";
          wantedBy = [ "multi-user.target" ];
          requires = [
            "toh-secrets-initialized.target"
            "openbao.service"
          ];
          after = [
            "toh-secrets-initialized.target"
            "openbao.service"
          ];
          path = [ pkgs.tohPackages.openbao-init ];
          script = "openbao-init";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
          };
        };

        toh.meta.sops.secrets = lib.mkMerge (
          [
            {
              "openbao-admin-pass" = {
                owner = user;
                group = group;
                mode = "0400";
              };
            }
          ]
          ++ builtins.map (machine: {
            "openbao-machine-${machine.name}-pass" = {
              owner = user;
              group = group;
              mode = "0400";
            };
          }) config.toh.meta.cluster.machinea
        );

        toh.meta.cryl.machine =
          builtins.map (machine: {
            "openbao-${machine.name}-password" = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/openbao-machine-${machine.name}-pass";
                    to = "openbao-machine-${machine.name}-pass";
                  };
                }
              ];
            };
          }) config.toh.meta.cluster.machinea
          ++ [
            {
              openbao-admin = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/openbao-admin-pass";
                      to = "openbao-admin-pass";
                    };
                  }
                ];
              };
            }
          ];

        toh.meta.cryl.cluster =
          builtins.map (machine: {
            "openbao-${machine.name}-password" = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "openbao-machine-${machine.name}-pass";
                  };
                }
              ];
            };
          }) config.toh.meta.cluster.machinea
          ++ [
            {
              openbao-admin = {
                generations = [
                  {
                    generator = "key";
                    arguments = {
                      name = "openbao-admin-pass";
                    };
                  }
                ];
              };
            }
          ];

        toh.services.openbao.createUserGroup = true;
      };
    };
}
