{ selfLib, ... }:

{
  self.nixosModules.services-maddy-apps.flake = true;
  self.nixosModules.services-maddy-apps.value =
    {
      lib,
      config,
      ...
    }:
    let
      anyMachines = selfLib.cluster.anyServiceMachines config "maddy";

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
              address = selfLib.email.makeAddress {
                inherit name;
                host = config.toh.meta.email.domain;
              };
              password = ldapUser.password;
            };
          }
        );

        toh.meta.ldap.apps = mergeByMachineApps (
          {
            name,
            user,
            group,
            ...
          }:
          {
            ${name} = {
              inherit user group;
              permissions = [ ];
            };
          }
        );
      };
    };
}
