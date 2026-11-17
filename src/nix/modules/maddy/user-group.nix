{
  toh.lib.nixosModules.services-maddy-user-group =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.maddy;
    in
    {
      options.toh.services = {
        maddy = {
          createUserGroup = lib.mkEnableOption "maddy user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${config.services.maddy.group} = { };

        users.users.${config.services.maddy.user} = {
          group = config.services.maddy.group;
          isSystemUser = true;
        };
      };
    };
}
