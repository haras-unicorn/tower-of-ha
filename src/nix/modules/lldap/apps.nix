{ selfLib, ... }:

{
  self.nixosModules.services-lldap-apps.flake = true;
  self.nixosModules.services-lldap-apps.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      name = "lldap";
      owner = name;
      group = name;

      anyMachines = selfLib.cluster.anyServiceMachines config "lldap";

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
          builtins.map (machine: machine.meta.ldap.apps) config.toh.meta.cluster.machineList
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
            password = config.toh.meta.sops.secrets."lldap-user-${name}-pass".path;
          };
        }
      );

      toh.services.lldap.init.userConfigs = mergeByClusterApps (
        { name, permissions, ... }:
        [
          {
            id = name;
            email = "${name}@${config.toh.meta.email.domain}";
            password_file = config.toh.meta.sops.secrets."lldap-app-${name}-pass".path;
            displayName = name;
            groups = builtins.filter (permission: permission != null) (
              builtins.map (
                permission:
                if permission == selfLib.ldap.permissions.readOnly then
                  "lldap_strict_readonly"
                else if permission == selfLib.ldap.permissions.passwordChange then
                  "lldap_password_manager"
                else
                  builtins.throw "Case not handled for permission '${permission}'"
              ) permissions
            );
          }
        ]
      );

      toh.meta.sops.secrets = lib.mkMerge [
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

      toh.meta.cryl.machine = lib.mkMerge [
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

      toh.meta.cryl.cluster = mergeByClusterApps (
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
