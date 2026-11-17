{
  toh.lib.nixosModules.services-openbao-user-group =
    {
      config,
      tohLib,
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
        users.groups.${tohLib.openbao.user} = { };

        users.users.${tohLib.openbao.group} = {
          group = tohLib.openbao.group;
          isSystemUser = true;
        };
      };
    };
}
