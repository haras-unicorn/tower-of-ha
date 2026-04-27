{
  flake.nixosModules.services-seaweedfs-home-mount =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      hosts = (
        builtins.filter (
          x:
          if lib.hasAttrByPath [ "system" "toh" "seaweedfs" "enable" ] x then
            x.system.toh.seaweedfs.enable
          else
            false
        ) config.toh.host.hosts
      );

      mountDir = "${config.toh.host.home}/weed";
    in
    {
      options.toh = {
        seaweedfs = {
          enableHomeMount = lib.mkEnableOption "SeaweedFS home mount";
        };
      };

      config = lib.mkIf config.toh.seaweedfs.enableHomeMount {
        services.seaweedfs.mounts.toh.enable = true;
        services.seaweedfs.mounts.toh.mountDir = mountDir;
        services.seaweedfs.mounts.toh.mountUid = config.toh.host.uid;
        services.seaweedfs.mounts.toh.mountGid = config.toh.host.gid;
        services.seaweedfs.mounts.toh.filerPath = mountDir;
        services.seaweedfs.mounts.toh.filers = builtins.map (
          host:
          let
            filerConfig = host.system.services.seaweedfs.filers.toh;
            ip = filerConfig.ip;
            port = filerConfig.httpPort;

            filerUid = host.system.users.users.${filerConfig.user}.uid;
            filerGid = host.system.users.groups.${filerConfig.group}.gid;
          in
          {
            server = "${ip}:${builtins.toString port}";
            uid = filerUid;
            gid = filerGid;
          }
        ) hosts;
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
