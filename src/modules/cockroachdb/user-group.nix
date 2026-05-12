{
  toh.lib.nixosModules.services-cockroachdb-user-group =
    {
      config,
      tohLib,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;
    in
    {
      options.toh.services = {
        cockroachdb = {
          createUserGroup = lib.mkEnableOption "CockroachDB user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${config.services.cockroachdb.group} = { };

        users.users.${config.services.cockroachdb.user} = {
          group = config.services.cockroachdb.group;
          isSystemUser = true;
        };
      };
    };
}
