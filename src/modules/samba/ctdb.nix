{
  toh.lib.nixosModules.nixpkgs-ctdb =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.samba;

      settingsFormat = pkgs.formats.ini {
        listToValue = lib.concatMapStringsSep " " (lib.generators.mkValueStringDefault { });
      };

      scriptOptionsFormat = pkgs.formats.keyValue {
        listToValue = lib.concatMapStringsSep " " (lib.generators.mkValueStringDefault { });
      };

      # NOTE: rundir is in localstatedir + run/ctdb in ctdb/wscript
      # and localstatedir is /var in samba package
      # on nixos /var/run is a symlink to /run so this is correct
      runDir = "/run/ctdb";
      # NOTE: vardir is in localstatedir + lib/ctdb in ctdb/wscript
      # and localstatedir is /var in samba package
      varDir = "/var/lib/ctdb";
      # NOTE: etcdir is in sysconfdir + ctdb in ctdb/wscript
      # and sysconfdir is /etc in samba package
      etcDir = "/etc/ctdb";
      # NOTE: datadir is in package + share/ctdb
      # so there is no absolute data path
      dataSubpath = "share/ctdb";

      # NOTE: the samba suite requires /var/lib/samba to be mounted anyway
      # so the most natural location for this lock would be in that mount
      defaultLockPath = "/var/lib/samba/.ctdb.lock";

      defaultNodesPath = "${etcDir}/nodes";

      etcSubpath = lib.removePrefix "/etc/" etcDir;
      etcConfPath = "${etcSubpath}/ctdb.conf";

      expectedVarDirs = [
        "volatile"
        "persistent"
        "state"
      ];

      eventsSubpath = "events/legacy";
      defaultEventScripts = [
        "00.ctdb.script"
        "01.reclock.script"
        "05.system.script"
        "10.interface.script"
        "95.database.script"
      ];

      etcGlobalScriptOptionsPath = "${etcSubpath}/script.options";
      etcScriptOptionsPathTemplate = "${etcSubpath}/${eventsSubpath}/<name>.options";

      configFile = settingsFormat.generate "ctdb.conf" cfg.ctdb.settings;
    in
    {
      options.services.samba.ctdb = {
        enable = lib.mkEnableOption "CTDB";

        eventScripts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            defaultEventScripts
            ++ lib.optional cfg.smbd.enable "50.samba.script"
            ++ lib.optional cfg.winbindd.enable "49.winbind.script"
            ++ lib.optional cfg.nmbd.enable "48.netbios.script";
          description = "Event scripts to use with ";
        };

        globalScriptOptions = lib.mkOption {
          type = scriptOptionsFormat.type;
          default = { };
          description = "
            Global script options placed in /etc/${etcGlobalScriptOptionsPath}.

            Refer to <https://ctdb.samba.org/manpages/ctdb-script.options.5.html>
            for all available options.
          ";
        };

        scriptOptions = lib.mkOption {
          type = lib.types.attrsOf scriptOptionsFormat.type;
          default = { };
          description = "
            Script options placed in /etc/${etcScriptOptionsPathTemplate}.

            Refer to <https://ctdb.samba.org/manpages/ctdb-script.options.5.html>
            for all available options.
          ";
        };

        addresses = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                address = lib.mkOption {
                  type = lib.types.str;
                  example = "192.168.1.1/24";
                  description = "Public address IP in CIDR format.";
                };
                interface = lib.mkOption {
                  type = lib.types.str;
                  example = "eth0";
                  description = "Public address interface.";
                };
              };
            }
          );
          example = [
            {
              address = "192.168.1.1/24";
              interface = "eth0";
            }
            {
              address = "192.168.1.2/24";
              interface = "eth0";
            }
          ];
          description = ''
            List of public addresses in CIDR format with their interfaces.
            This gets written to /etc/ctdb/public_addresses.
          '';
        };

        nodes = lib.mkOption {
          type = lib.types.nonEmptyListOf lib.types.str;
          example = [
            "192.168.1.1"
            "192.168.1.2"
          ];
          description = ''
            List of cluster node IP addresses.
            This gets written to the file
            at configuration value "nodes list"
            at section [cluster] (default is /etc/ctdb/nodes).
          '';
        };

        settings = lib.mkOption {
          type = lib.types.submodule {
            freeformType = settingsFormat.type;
            options = {
              cluster."cluster lock" = lib.mkOption {
                type = lib.types.str;
                default = defaultLockPath;
                description = "Cluster lock path.";
              };
              cluster."nodes list" = lib.mkOption {
                type = lib.types.str;
                default = defaultNodesPath;
                description = "Nodes list file path.";
              };
              failover.disabled = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether to disable public IP failover.";
              };
              logging.location = lib.mkOption {
                type = lib.types.str;
                default = "syslog";
                description = "Where should CTDB output its logs.";
              };
            };
          };
          default = {
            cluster = {
              "cluster lock" = defaultLockPath;
              "nodes list" = defaultNodesPath;
            };
          };
          description = ''
            Configuration file for CTDB in ini format.
            This file is located in /etc/${etcConfPath}

            Refer to <https://ctdb.samba.org/manpages/ctdb.conf.5.html>
            for all available options.
          '';
        };
      };

      config = lib.mkIf (cfg.enable && cfg.ctdb.enable) {
        systemd.tmpfiles.rules = builtins.map (dir: "d ${varDir}/${dir} 0750 root root -") expectedVarDirs;

        environment.etc = lib.mkMerge [
          {
            ${etcConfPath}.source = configFile;
            "${etcSubpath}/functions".source = "${cfg.package}/etc/${etcSubpath}/functions";
            "${etcSubpath}/notify.sh".source = "${cfg.package}/etc/${etcSubpath}/notify.sh";
            "${etcSubpath}/public_addresses".text =
              (builtins.concatStringsSep "\n" (
                builtins.map ({ address, interface }: "${address} ${interface}") cfg.ctdb.addresses
              ))
              + "\n";
            ${etcGlobalScriptOptionsPath}.source =
              scriptOptionsFormat.generate "script.options" cfg.ctdb.globalScriptOptions;
          }
          (builtins.listToAttrs (
            builtins.map (script: {
              name = "${etcSubpath}/${eventsSubpath}/${script}";
              value.source = "${cfg.package}/${dataSubpath}/${eventsSubpath}/${script}";
            }) cfg.ctdb.eventScripts
          ))
          (lib.mapAttrs' (script: content: {
            name = "${etcSubpath}/${eventsSubpath}/${script}.options";
            value.source = scriptOptionsFormat.generate "${script}.options" content;
          }) cfg.ctdb.scriptOptions)
        ];

        system.activationScripts.ctdbNodes = {
          text =
            let
              file = lib.escapeShellArg cfg.ctdb.settings.cluster."nodes list";
              dir = lib.escapeShellArg (builtins.dirOf cfg.ctdb.settings.cluster."nodes list");
              template = lib.escapeShellArg (
                builtins.concatStringsSep "" (builtins.map (_: ''%s\n'') cfg.ctdb.nodes)
              );
              nodes = lib.escapeShellArgs cfg.ctdb.nodes;
            in
            ''
              mkdir -p ${dir}
              printf ${template} ${nodes} > ${file}
            '';
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
          4379
        ];

        # NOTE: config per packaging/systemd/ctdb.service.in
        # and other samba daemons
        systemd.services.samba-ctdb = {
          description = "Samba CTDB daemon";
          documentation = [
            "man:ctdbd(1)"
            "man:ctdb(7)"
          ];
          wantedBy = [ "samba.target" ];
          partOf = [ "samba.target" ];
          before =
            lib.optional cfg.smbd.enable "samba-smbd.service"
            ++ lib.optional cfg.nmbd.enable "samba-nmbd.service"
            ++ lib.optional cfg.winbindd.enable "samba-winbindd.service";
          after = [
            "network.target"
            "network-online.target"
            "time-sync.target"
          ];
          wants = [
            "network-online.target"
            "time-sync.target"
          ];

          environment.LD_LIBRARY_PATH = config.system.nssModules.path;

          restartTriggers = [ configFile ];

          # NOTE: needed at least for default scripts to work properly
          path = [
            cfg.package
            pkgs.gawk
            pkgs.killall
            pkgs.tdb
            pkgs.util-linux
            pkgs.ethtool
            pkgs.iproute2
            pkgs.iptables
          ];

          unitConfig = {
            ConditionFileNotEmpty = cfg.ctdb.settings.cluster."nodes list";
            RequiresMountsFor = "/var/lib/samba";
          };

          serviceConfig = {
            Type = "forking";
            LimitCORE = "infinity";
            LimitNOFILE = 1048576;
            TasksMax = 4096;
            PIDFile = "${runDir}/ctdbd.pid";
            RuntimeDirectory = lib.removePrefix "/run/" runDir;
            ExecStart = "${cfg.package}/sbin/ctdbd";
            ExecStop = "${cfg.package}/bin/ctdb shutdown";
            KillMode = "control-group";
            Restart = "no";
            StateDirectory = lib.removePrefix "/var/lib/" varDir;
            Slice = "system-samba.slice";
            SyslogIdentifier = "samba-ctdb";
          };
        };
      };
    };
}
