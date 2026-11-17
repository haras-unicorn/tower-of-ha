{
  self.nixosModules.services-forgejo-user-group.flake = true;
  self.nixosModules.services-forgejo-user-group.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      name = "forgejo";
      owner = name;
      group = name;
    in
    {
      options.toh.services = {
        forgejo = {
          createUserGroup = lib.mkEnableOption "forgejo user and group creation";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${group} = { };

        users.users.${owner} = {
          home = lib.mkForce "/var/empty";
          useDefaultShell = lib.mkForce false;
          group = group;
          isSystemUser = true;
        };
      };
    };
}
