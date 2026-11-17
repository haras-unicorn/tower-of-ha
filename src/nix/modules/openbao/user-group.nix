{ selfLib, ... }:

{
  self.nixosModules.services-openbao-user-group.flake = true;
  self.nixosModules.services-openbao-user-group.value =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.openbao;
    in
    {
      options.toh.services = {
        openbao = {
          createUserGroup = lib.mkEnableOption "OpenBao user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${selfLib.openbao.user} = { };

        users.users.${selfLib.openbao.group} = {
          group = selfLib.openbao.group;
          isSystemUser = true;
        };
      };
    };
}
