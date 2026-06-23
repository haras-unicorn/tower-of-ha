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
                preMount = "ceph-pre-mount-${baseName}";
                postMount = "ceph-post-mount-${baseName}";
                mount = baseName;
              }
              // value
            )
          ) (lib.attrsToList mounts)
        );
    in
    {
      toh.meta.filesystem = {
        type = lib.mkIf anyMachines "ceph";
      };

      systemd.tmpfiles.rules = mergeByMount (
        {
          path,
          user,
          group,
          mode,
          ...
        }:
        [
          "d ${path} ${mode} ${user} ${group} -"
        ]
      );

      systemd.services = mergeByMount (
        {
          preMount,
          postMount,
          erase,
          path,
          user,
          group,
          directory,
          mode,
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
          ${preMount} = {
            description = "Pre mount CephFS at '${path}'";
            wantedBy = afterServices;
            after = afterServices;
            requires = afterServices;
            path = [ pkgs.ceph ];
            script = ''
              ${lib.optionalString erase ''
                shopt -s extglob
                shopt -s dotglob
                rm -rf "${path}"/*
                shopt -u extglob
                shopt -u dotglob
              ''}

              while ! ceph fs status --format json \
                | grep '"state": "active"' >/dev/null 2>&1; do
                echo "Waiting for MDS..."
                sleep 1
              done

              cephfs-shell "mkdir -p -m ${mode} '${directory}'"
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
          };

          ${postMount} = {
            description = "Post mount CephFS at '${path}'";
            wantedBy = afterServices;
            after = afterServices;
            requires = afterServices;
            path = [ pkgs.ceph ];
            script = ''
              chown ${user}:${group} '${path}'
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
          };
        }
      );

      systemd.mounts = mergeByMount (
        {
          path,
          preMount,
          postMount,
          directory,
          ...
        }:
        [
          {
            what = "admin@.ceph=${directory}";
            where = path;
            type = "ceph";
            wantedBy = [
              "${preMount}.service"
              "${postMount}.service"
            ];
            bindsTo = [
              "${preMount}.service"
              "${postMount}.service"
            ];
            after = [ "${preMount}.service" ];
            before = [ "${postMount}.service" ];
            unitConfig.DefaultDependencies = false;
          }
        ]
      );

      systemd.targets.toh-filesystem-online = mergeByMount (
        {
          preMount,
          postMount,
          mount,
          ...
        }:
        {
          wantedBy = [
            "${preMount}.service"
            "${mount}.mount"
            "${postMount}.service"
          ];
          bindsTo = [
            "${preMount}.service"
            "${mount}.mount"
            "${postMount}.service"
          ];
          after = [
            "${preMount}.service"
            "${mount}.mount"
            "${postMount}.service"
          ];
        }
      );

      users.groups.fuse = lib.mkIf anyMounts { };
      users.users.ceph = lib.mkIf anyMounts {
        extraGroups = [ "fuse" ];
      };
      programs.fuse.userAllowOther = true;

      toh.services.cephfs.createUserGroup = lib.mkIf anyMounts true;
      toh.services.cephfs.installAdminKeyring = lib.mkIf anyMounts true;
    };
}
