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
      ) (lib.filterAttrs (_: { share, ... }: share != null) mounts);

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
          toh.meta.filesystem.mounts."/var/lib/samba" = {
            erase = true;
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

                "usershare path" = "/var/lib/samba/usershares";
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

          # NOTE: smbd keeps its state in tdb files on CephFS, which only one
          # smbd may use at a time
          toh.leases.samba.services = [ "samba-smbd" ];

          systemd.services.samba-smbd.serviceConfig.Restart = "on-failure";

          systemd.services.samba-dirs = {
            description = "Ensure Samba directories exist";
            wantedBy = [ "samba.target" ];
            partOf = [ "samba.target" ];
            before = [ "samba-smbd.service" ];

            unitConfig = {
              RequiresMountsFor = "/var/lib/samba";
            };

            script = ''
              mkdir -p /var/lib/samba/private /var/lib/samba/usershares /var/lib/samba/userdata
              chown root:root /var/lib/samba/private /var/lib/samba/usershares
              chmod 700 /var/lib/samba/private
              chmod 750 /var/lib/samba/userdata
              chmod 1770 /var/lib/samba/usershares
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
