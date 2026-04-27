{
  toh.lib.nixosModules.services-cockroachdb-user-group =
    {
      config,
      tohLib,
      lib,
      ...
    }:
    let
      anyMachines = tohLib.anyServiceMachines "cockroachdb";
    in
    {
      users.groups.${config.services.cockroachdb.group} = lib.mkIf anyMachines { };

      users.users.${config.services.cockroachdb.user} = lib.mkIf anyMachines {
        group = config.services.cockroachdb.group;
        isSystemUser = true;
      };
    };
}
