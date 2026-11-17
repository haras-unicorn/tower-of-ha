{
  self.nixosModules.services-lldap-user-group.flake = true;
  self.nixosModules.services-lldap-user-group.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.lldap;

      name = "lldap";
      owner = name;
      group = name;
    in
    {
      options.toh.services = {
        lldap = {
          createUserGroup = lib.mkEnableOption "LLDAP user and group creation";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${group} = { };

        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };
      };
    };
}
