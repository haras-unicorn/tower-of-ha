{
  toh.lib.nixosModules.services-lldap-apps =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      name = "lldap";
      owner = name;
      group = name;

      anyMachines = tohLib.anyServiceMachines "lldap";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
          }
        ) (lib.attrsToList apps);

      machineApps = appAttrsToList config.toh.meta.ldap.apps;

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.ldap.apps) config.toh.cluster.machinea
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));
    in
    {
      toh.meta.ldap.users = mergeByMachineApps (
        { name, ... }:
        {
          ${name} = {
            dn = "uid=${name},ou=people,${config.toh.meta.ldap.baseDistinguishedName}";
            password = config.sops.secrets."lldap-user-${name}-pass".path;
          };
        }
      );

      toh.services.lldap.init.userConfigs = mergeByClusterApps (
        { name, permissions, ... }:
        [
          {
            id = name;
            email = "${name}@${config.toh.meta.email.domain}";
            password_file = config.sops.secrets."lldap-app-${name}-pass".path;
            displayName = name;
            groups = builtins.filter (permission: permission != null) (
              builtins.map (
                permission:
                if permission == tohLib.ldap.permissions.readOnly then
                  "lldap_strict_readonly"
                else if permission == tohLib.ldap.permissions.passwordChange then
                  "lldap_password_manager"
                else
                  builtins.throw "Case not handled for permission '${permission}'"
              ) permissions
            );
          }
        ]
      );

      sops.secrets = lib.mkMerge [
        (mergeByClusterApps (
          { name, ... }:
          {
            "lldap-app-${name}-pass" = {
              inherit owner group;
              mode = "0400";
            };
          }
        ))
        (mergeByMachineApps (
          { name, ... }@app:
          {
            "lldap-user-${name}-pass" = {
              owner = app.user;
              group = app.group;
              mode = "0400";
            };

          }
        ))
      ];

      toh.cryl.machine = lib.mkMerge [
        (mergeByClusterApps (
          { name, ... }:
          [
            {
              "lldap-app-${name}-pass" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/lldap-${name}-pass";
                      to = "lldap-app-${name}-pass";
                    };
                  }
                ];
              };
            }
          ]
        ))
        (mergeByMachineApps (
          { name, ... }:
          [
            {
              "lldap-user-${name}-pass" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/lldap-${name}-pass";
                      to = "lldap-user-${name}-pass";
                    };
                  }
                ];
              };
            }
          ]
        ))
      ];

      toh.cryl.cluster = mergeByClusterApps (
        { name, ... }:
        [
          {
            "lldap-${name}" = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "lldap-${name}-pass";
                  };
                }
              ];
            };
          }
        ]
      );
    };
}
