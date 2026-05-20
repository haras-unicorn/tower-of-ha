{
  toh.lib.nixosModules.services-ceph-admin =
    {
      lib,
      pkgs,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.cephfs;

      machines = tohLib.serviceMachines "cephfs";
      ips = builtins.concatStringsSep "," (builtins.map (machine: machine.meta.network.ip) machines);
      fsid = config.toh.services.cephfs.fsid;
    in
    {
      options.toh.services = {
        cephfs = {
          installAdminKeyring = lib.mkEnableOption "CephFS admin keyring installation";

          generateAdminKeyring = lib.mkEnableOption "CephFS admin keyring generation";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.installAdminKeyring {
          toh.services.cephfs.generateAdminKeyring = true;

          environment.etc."ceph/ceph.conf" = lib.mkIf (!cfg.enable) {
            user = "ceph";
            group = "ceph";
            mode = "0400";
            text = ''
              [global]
              fsid = ${fsid}
              mon host = ${ips}
            '';
          };

          sops.secrets."cephfs-admin-keyring" = {
            path = "/etc/ceph/ceph.client.admin.keyring";
            owner = "ceph";
            group = "ceph";
            mode = "0400";
          };
        })
        (lib.mkIf cfg.generateAdminKeyring {
          toh.cryl.machine = [
            {
              cephfs-admin = {
                generations = [
                  {
                    generator = "mustache";
                    arguments = {
                      name = "cephfs-admin-keyring";
                      renew = true;
                      listing = {
                        type = "map";
                        value = {
                          CEPH_ADMIN_KEY = "cluster/cephfs-admin-key";
                        };
                      };
                      template = ''
                        [client.admin]
                        key = {{{CEPH_ADMIN_KEY}}}
                        caps mon = "allow *"
                        caps osd = "allow *"
                        caps mds = "allow *"
                        caps mgr = "allow *"
                      '';
                    };
                  }
                ];
              };
            }
          ];

          toh.cryl.cluster = [
            {
              cephfs-admin = {
                generations = [
                  {
                    generator = "ceph-key";
                    arguments.name = "cephfs-admin-key";
                  }
                ];
              };
            }
          ];
        })
      ];
    };
}
