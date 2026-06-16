{
  toh.lib.nixosModules.services-garage-apps =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.garage;

      anyMachines = tohLib.anyServiceMachines "garage";

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
          builtins.map (machine: machine.meta.s3.apps) config.toh.meta.cluster.machinea
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
