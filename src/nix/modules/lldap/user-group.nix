{
  toh.lib.nixosModules.services-lldap-user-group =
    {
      lib,
      tohLib,
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
