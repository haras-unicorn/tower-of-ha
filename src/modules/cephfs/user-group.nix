{
  toh.lib.nixosModules.services-cephfs-user-group =
    {
      config,
      tohLib,
      lib,
      ...
    }:
    let
      cfg = config.toh.services.cephfs;
    in
    {
      options.toh.services = {
        cephfs = {
          createUserGroup = lib.mkEnableOption "CephFS user and group";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.ceph = { };

        users.users.ceph = {
          group = "ceph";
          isSystemUser = true;
        };
      };
    };
}
