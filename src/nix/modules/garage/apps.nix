{ selfLib, ... }:

{
  self.nixosModules.services-garage-apps.flake = true;
  self.nixosModules.services-garage-apps.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.garage;

      anyMachines = selfLib.cluster.anyServiceMachines config "garage";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
            garageUser = config.toh.services.garage.users.${name};
          }
        ) (lib.attrsToList apps);

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.s3.apps) config.toh.meta.cluster.machineList
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.s3.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));
    in
    {
      toh.meta.s3.buckets = mergeByMachineApps (
        {
          name,
          garageUser,
          ...
        }:
        {
          ${name} = {
            keyId = garageUser.keyId;
            secretKey = garageUser.secretKey;
          };
        }
      );

      toh.services.garage.users = lib.mkMerge [
        (mergeByMachineApps (
          {
            name,
            group,
            user,
            ...
          }:
          {
            ${name} = {
              installSecrets = true;
              inherit group user;
            };
          }
        ))
        (mergeByClusterApps (
          {
            name,
            group,
            user,
            ...
          }:
          {
            ${name} = {
              generateSecrets = true;
              inherit group user;
            };
          }
        ))
      ];
    };
}
