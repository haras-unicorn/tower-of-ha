{
  toh.lib.nixosModules.services-seaweedfs-home-mount =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.seaweedfs;

      machines = tohLib.serviceMachines "seaweedfs";

      mountDir = "${config.toh.meta.user.home}/weed";
    in
    {
      options.toh.services = {
        seaweedfs = {
          enableHomeMount = lib.mkEnableOption "SeaweedFS home mount";
        };
      };

      config = lib.mkIf cfg.enableHomeMount {
        services.seaweedfs.mounts.toh.enable = true;
        services.seaweedfs.mounts.toh.mountDir = mountDir;
        services.seaweedfs.mounts.toh.mountUid = config.toh.meta.user.uid;
        services.seaweedfs.mounts.toh.mountGid = config.toh.meta.user.gid;
        services.seaweedfs.mounts.toh.filerPath = mountDir;
        services.seaweedfs.mounts.toh.filers = builtins.map (
          machine:
          let
            filerConfig = machine.config.services.seaweedfs.filers.toh;
            ip = filerConfig.ip;
            port = filerConfig.httpPort;

            filerUid = machine.config.users.users.${filerConfig.user}.uid;
            filerGid = machine.config.users.groups.${filerConfig.group}.gid;
          in
          {
            server = "${ip}:${builtins.toString port}";
            uid = filerUid;
            gid = filerGid;
          }
        ) machines;
        systemd.services."seaweedfs-mount@toh".wantedBy = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services."seaweedfs-mount@toh".after = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services."seaweedfs-mount@toh".requires = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
      };
    };
}
