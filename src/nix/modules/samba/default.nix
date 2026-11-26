{ selfLib, ... }:

{
  self.nixosModules.services-samba.flake = true;
  self.nixosModules.services-samba.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.samba;

      mounts = config.toh.meta.filesystem.mounts;

      sharedMounts = lib.filterAttrs (_: { share, ... }: share != null) mounts;

      mountShares = lib.mapAttrs' (
        path:
        { share, ... }:
        lib.nameValuePair share.name {
          inherit path;
          "read only" = "no";
          "browseable" = "yes";
          "create mask" = share.fileMask;
          "directory mask" = share.directoryMask;
          "access based share enum" = "yes";
        }
      ) sharedMounts;

      usersharesDirectory = "/var/lib/samba/usershares";
      userdataDirectory = "/var/lib/samba/userdata";

      services = [
        "toh-lease-samba.service"
        "samba-dirs.service"
      ];

      anyMachines = selfLib.cluster.anyServiceMachines config "samba";

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.samba.endpoint;
    in
    {
      options.toh.services = {
        samba = {
          enable = lib.mkEnableOption "Samba";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.share = {
            host = proxyAttrs.host;
            port = proxyAttrs.port;
          };
        })
        (lib.mkIf cfg.enable {
          # NOTE: Samba keeps its databases (passwords, secrets, locks) in
          # tdb files, which it only shares between machines through CTDB;
          # on CephFS a takeover inherits them in whatever state the dead
          # machine left, so they stay local and only the user shares and
          # their files are shared
          toh.meta.filesystem.mounts = {
            ${usersharesDirectory} = { };
            ${userdataDirectory} = { };
          };

          services.samba = {
            enable = true;
            settings = mountShares // {
              global = {
                "bind interfaces only" = "yes";
                "interfaces" = [
                  "127.0.0.1"
                  config.toh.meta.network.ip
                ];

                "workgroup" = "TOH";
                "server role" = "standalone";
                "security" = "user";

                "logging" = "systemd";
                "log level" = 1;

                "server min protocol" = "SMB3_00";
                "server max protocol" = "SMB3_11";
                "client smb encrypt" = "required";

                # NOTE: smbd answers a write before it is on disk unless the
                # client asks for a flush, so a write could sit in the CephFS
                # cache of a machine that dies right after; this syncs every
                # write to CephFS first, which is slower but keeps it
                "sync always" = "yes";
                "strict sync" = "yes";

                "usershare path" = usersharesDirectory;
                "usershare max shares" = 255;
                "usershare allow guests" = false;
                "usershare template share" = "usershare";
              };
              "usershare" = {
                "path" = "/tmp/samba/usershare";
                "read only" = "no";
                "browseable" = "yes";
                "create mask" = "0640";
                "directory mask" = "0750";
                "access based share enum" = "yes";
              };
            };
            openFirewall = true;

            winbindd = {
              enable = false;
            };

            nmbd = {
              enable = false;
            };
          };

          # NOTE: without CTDB, two smbd do not know each other's locks on the
          # same files, so only one may serve the shares at a time
          toh.leases.samba.services = [ "samba-smbd" ];

          systemd.services.samba-smbd = {
            serviceConfig.Restart = "on-failure";
            # NOTE: the state of smbd is local, so without this it could serve
            # the empty directories under the CephFS mounts of its shares
            unitConfig.RequiresMountsFor = [
              usersharesDirectory
              userdataDirectory
            ]
            ++ builtins.attrNames sharedMounts;
          };

          systemd.services.samba-dirs = {
            description = "Ensure Samba directories exist";
            wantedBy = [ "samba.target" ];
            partOf = [ "samba.target" ];
            before = [ "samba-smbd.service" ];

            unitConfig = {
              RequiresMountsFor = [
                usersharesDirectory
                userdataDirectory
              ];
            };

            script = ''
              mkdir -p /var/lib/samba/private
              chown root:root /var/lib/samba/private ${usersharesDirectory}
              chmod 700 /var/lib/samba/private
              chmod 750 ${userdataDirectory}
              chmod 1770 ${usersharesDirectory}
            '';
          };

          systemd.targets.toh-filesystem-online = {
            wantedBy = services;
            after = services;
            requires = services;
          };

          toh.meta.services.samba = {
            endpoint.tcp = {
              port = 445;
              layer7Protocol = "smb";
              persistIp = true;
              sslTermination = "passthrough";
            };
          };
        })
      ];
    };
}
