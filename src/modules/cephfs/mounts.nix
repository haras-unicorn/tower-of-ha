{
  toh.lib.nixosModules.services-ceph-mounts =
    {
      lib,
      tohLib,
      pkgs,
      config,
      ...
    }:
    let
      anyMachines = tohLib.anyServiceMachines "cephfs";

      monDaemons = builtins.map (daemon: "ceph-mon-${daemon}.service") config.services.ceph.mon.daemons;

      cfg = config.toh.services.cephfs;

      mounts = config.toh.meta.filesystem.mounts;

      anyMounts = builtins.length (builtins.attrNames mounts) != 0;

      data = "/var/lib/ceph/mounts";

      mergeByMount =
        forEachMount:
        lib.mkMerge (
          builtins.map (
            { name, value }:
            let
              baseName = builtins.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" name);
            in
            forEachMount (
              {
                path = name;
                name = baseName;
                mount = "${data}/${baseName}";
                service = "ceph-mount-${baseName}";
                bind = baseName;
              }
              // value
            )
          ) (lib.attrsToList mounts)
        );
    in
    {
      toh.meta.filesystem = {
        type = lib.mkIf anyMachines "cephfs";
      };

      systemd.tmpfiles.rules = mergeByMount (
        {
          path,
          mount,
          user,
          group,
          mode,
          ...
        }:
        [
          "d ${data} 0750 ceph ceph -"
          "d ${mount} 0750 ceph ceph -"
          "d ${path} ${mode} ${user} ${group} -"
        ]
      );

      systemd.services = mergeByMount (
        {
          service,
          path,
          mount,
          user,
          group,
          directory,
          ...
        }:
        let
          afterServices = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ]
          ++ lib.optionals cfg.enable (
            [
              "ceph-fs-ensure-volume.service"
            ]
            ++ monDaemons
          );
        in
        {
          ${service} = {
            description = "Mount CephFS at '${path}'";
            wantedBy = afterServices;
            after = afterServices;
            requires = afterServices;
            path = [
              pkgs.ceph
              pkgs.fuse
            ];
            script =
              let
                subDir = if directory == null then "" else ''-r "${directory}"'';
              in
              ''
                while ! ceph fs status --format json \
                  | grep '"state": "active"' >/dev/null 2>&1; do
                  echo "Waiting for MDS..."
                  sleep 1
                done

                ceph-fuse "${mount}" ${subDir} \
                  -n client.admin \
                  -o allow_other
              '';
            postStop = ''
              fusermount -u "${mount}"
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "ceph";
              Group = "ceph";
              SupplementaryGroups = [ "fuse" ];
            };
          };
        }
      );

      systemd.mounts = mergeByMount (
        {
          path,
          mount,
          service,
          ...
        }:
        [
          {
            what = mount;
            where = path;
            type = "none";
            options = "bind";
            wantedBy = [ "${service}.service" ];
            bindsTo = [ "${service}.service" ];
            after = [ "${service}.service" ];
            unitConfig.DefaultDependencies = false;
          }
        ]
      );

      systemd.targets.toh-filesystem-initialized = mergeByMount (
        { service, bind, ... }:
        {
          wantedBy = [
            "${service}.service"
            "${bind}.mount"
          ];
          bindsTo = [
            "${service}.service"
            "${bind}.mount"
          ];
          after = [
            "${service}.service"
            "${bind}.mount"
          ];
        }
      );

      users.groups.fuse = lib.mkIf anyMounts { };
      users.users.ceph.extraGroups = lib.mkIf anyMounts [ "fuse" ];
      programs.fuse.userAllowOther = true;

      toh.services.cephfs.createUserGroup = lib.mkIf anyMounts true;
      toh.services.cephfs.installAdminKeyring = lib.mkIf anyMounts true;
    };
}
