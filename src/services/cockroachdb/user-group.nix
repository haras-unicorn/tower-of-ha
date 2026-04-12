{
  flake.nixosModules.services-cockroachdb-user-group =
    { config, ... }:
    {
      users.groups.${config.services.cockroachdb.group} = { };

      users.users.${config.services.cockroachdb.user} = {
        group = config.services.cockroachdb.group;
        isSystemUser = true;
      };
    };
}
