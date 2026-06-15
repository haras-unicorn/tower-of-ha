{
  toh.lib.nixosModules.services-maddy-apps =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.maddy;

      anyMachines = tohLib.anyServiceMachines "maddy";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
            ldapUser = config.toh.meta.ldap.users.${name};
          }
        ) (lib.attrsToList apps);

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.email.apps) config.toh.cluster.machinea
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.email.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));
    in
    {
      config = {
        toh.meta.email.emails = mergeByMachineApps (
          { name, ldapUser, ... }:
          {
            ${name} = {
              address = tohLib.email.makeAddress {
                inherit name;
                host = config.toh.meta.email.domain;
              };
              password = ldapUser.password;
            };
          }
        );

        toh.meta.ldap.apps = mergeByClusterApps (
          { name, ... }:
          {
            ${name} = {
              user = name;
              group = name;
              permissions = [ ];
            };
          }
        );
      };
    };
}
