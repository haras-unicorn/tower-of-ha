{
  toh.lib.nixosModules.services-samba =
    {
      lib,
      pkgs,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.samba;

      machines = tohLib.serviceMachines "samba";
      machineIps = builtins.map (machine: machine.meta.network.ip) machines;

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
        "samba-ctdb.service"
        "samba-smbd.service"
        "samba-dirs.service"
      ];
    in
    {
      options.toh.services = {
        samba = {
          enable = lib.mkEnableOption "Samba";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.meta.filesystem.mounts."/var/lib/samba" = {
          erase = true;
        };

        services.samba = {
          enable = true;
          package = pkgs.tohPackages.sambaCtdb;
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

              "clustering" = "yes";

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

          ctdb = {
            enable = true;
            eventScripts = [
              "00.ctdb.script"
              "01.reclock.script"
              "05.system.script"
              "95.database.script"
            ];
            addresses = [ ];
            nodes = machineIps;
            settings = {
              cluster."node address" = config.toh.meta.network.ip;
              failover.disabled = true;
            };
          };

          winbindd = {
            enable = false;
          };

          nmbd = {
            enable = false;
          };
        };

        environment.etc."ctdb/events/legacy/50.samba.script" = {
          mode = "0700";
          text = ''
            #!/bin/sh
            . "''${CTDB_BASE}/functions"
            service_name="samba"
            load_script_options

            case "$1" in
              startup)
                touch /var/lib/ctdb/samba || die "smbd not running"
                ;;
              shutdown)
                rm /var/lib/ctdb/samba || die "smbd not running"
                ;;
              monitor)
                smb_ports="''${CTDB_SAMBA_CHECK_PORTS:-445}"
                ctdb_check_tcp_ports $smb_ports || exit $?
                ;;
            esac
            exit 0
          '';
        };

        systemd.services.samba-smbd = {
          unitConfig.ConditionFileExists = "/var/lib/ctdb/samba";
          serviceConfig.Restart = "on-failure";
        };

        systemd.services.samba-dirs = {
          description = "Ensure Samba directories exist";
          wantedBy = [ "samba.target" ];
          partOf = [ "samba.target" ];
          before = [
            "samba-ctdb.service"
            "samba-smbd.service"
          ];

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
      };
    };
}
