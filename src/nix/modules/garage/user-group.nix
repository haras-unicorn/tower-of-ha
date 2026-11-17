{
  toh.lib.nixosModules.services-garage-user-group =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.garage;
    in
    {
      options.toh.services = {
        garage = {
          createUserGroup = lib.mkEnableOption "garage user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.garage = { };

        users.users.garage = {
          group = "garage";
          isSystemUser = true;
        };
      };
    };
}
