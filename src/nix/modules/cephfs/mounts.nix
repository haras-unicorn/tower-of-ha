{ selfLib, ... }:

{
  self.nixosModules.services-ceph-mounts.flake = true;
  self.nixosModules.services-ceph-mounts.value =
    {
      lib,
      pkgs,
      config,
      utils,
      ...
    }:
    let
      cephPackage = pkgs.ceph;

      anyMachines = selfLib.cluster.anyServiceMachines config "cephfs";

      monDaemons = builtins.map (daemon: "ceph-mon-${daemon}.service") config.services.ceph.mon.daemons;

      cfg = config.toh.services.cephfs;

      mounts = config.toh.meta.filesystem.mounts;

      anyMounts = builtins.length (builtins.attrNames mounts) != 0;

      mountSource =
        directory:
        if cfg.mountDriver == "fuse" then
          {
            what = "none";
            type = "fuse.ceph";
            options = "ceph.id=admin,ceph.client_fs=ceph,ceph.client_mountpoint=${directory}";
          }
        else
          {
            what = "admin@.ceph=${directory}";
            type = "ceph";
          };

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
                # NOTE: systemd escapes a dash inside a path component, so the
                # unit of '/var/lib/matrix-synapse' is not named like its path
                # with the slashes swapped
                mount = utils.escapeSystemdPath name;
              }
              // value
            )
          ) (lib.attrsToList mounts)
        );
    in
    {
      options.toh.services.cephfs.mountDriver = lib.mkOption {
        type = lib.types.enum [
          "kernel"
          "fuse"
        ];
        default = "kernel";
        description = ''
          How machines mount CephFS. The kernel client is faster, ceph-fuse
          runs in user space and needs no kernel support for the key type.
        '';
      };

      config = {
        toh.meta.filesystem = {
          type = lib.mkIf anyMachines "cephfs";
        };

        system.fsPackages = lib.mkIf anyMounts [ cephPackage ];

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
              path = [ cephPackage ];
              # NOTE: cephfs-shell imports distro, which the python env of
              # nixpkgs' ceph lacks; adding it there rebuilds all of ceph
              environment.PYTHONPATH = lib.makeSearchPath cephPackage.pythonEnv.sitePackages [
                cephPackage.pythonEnv.pkgs.distro
              ];
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

                output=$(cephfs-shell "mkdir -p -m ${mode} '${directory}'" 2>&1) \
                  || echo "$output" | grep -q 'ObjectExists'
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
              path = [ cephPackage ];
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
            (
              mountSource directory
              // {
                where = path;
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
            )
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
    };
}
