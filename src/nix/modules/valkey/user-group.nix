{
  self.nixosModules.services-valkey-user-group.flake = true;
  self.nixosModules.services-valkey-user-group.value =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.valkey;
    in
    {
      options.toh.services = {
        valkey = {
          createUserGroup = lib.mkEnableOption "valkey user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.valkey = { };

        users.users.valkey = {
          group = "valkey";
          isSystemUser = true;
        };
      };
    };
}
