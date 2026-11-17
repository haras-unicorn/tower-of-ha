{
  toh.lib.nixosModules.services-patroni-user-group =
    {
      config,
      tohLib,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.patroni;
    in
    {
      options.toh.services = {
        patroni = {
          createUserGroup = lib.mkEnableOption "patroni user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${config.services.patroni.group} = { };

        users.users.${config.services.patroni.user} = {
          group = config.services.patroni.group;
          isSystemUser = true;
        };
      };
    };
}
