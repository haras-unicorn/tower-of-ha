{
  self.nixosModules.services-node-exporter.flake = true;
  self.nixosModules.services-node-exporter.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.node-exporter;

      # NOTE: filesystems that live in memory or are made of other ones, so
      # their free space says nothing about the disks
      virtualFilesystems = "tmpfs|ramfs|squashfs|overlay|fuse.*";
    in
    {
      options.toh.services.node-exporter = {
        enable = lib.mkEnableOption "the metrics of the machine itself: CPU, memory, disks, network and systemd units";

        port = lib.mkOption {
          type = lib.types.port;
          default = 9100;
          description = "Port of the node exporter.";
        };

        alerts = {
          diskFreeRatio = lib.mkOption {
            type = lib.types.float;
            default = 0.1;
            description = "Share of a filesystem that has to stay free, below which it is an alert.";
          };

          memoryFreeRatio = lib.mkOption {
            type = lib.types.float;
            default = 0.1;
            description = "Share of the memory that has to stay free, below which it is an alert.";
          };

          for = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "How long a machine may be short on disk or memory before it is an alert.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = config.toh.meta.network.ip;
          inherit (cfg) port;
          enabledCollectors = [ "systemd" ];
        };

        systemd.services.prometheus-node-exporter = {
          wantedBy = [ "toh-network-online.target" ];
          after = [ "toh-network-online.target" ];
          requires = [ "toh-network-online.target" ];
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        toh.meta.metrics.targets.node.port = cfg.port;

        toh.meta.metrics.alerts = {
          DiskAlmostFull = {
            expression = ''
              node_filesystem_avail_bytes{fstype!~"${virtualFilesystems}"}
                / node_filesystem_size_bytes{fstype!~"${virtualFilesystems}"}
                < ${builtins.toString cfg.alerts.diskFreeRatio}
            '';
            inherit (cfg.alerts) for;
            summary = "{{ $labels.mountpoint }} on {{ $labels.machine }} is almost full";
          };

          MemoryAlmostFull = {
            expression = ''
              node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
                < ${builtins.toString cfg.alerts.memoryFreeRatio}
            '';
            inherit (cfg.alerts) for;
            summary = "{{ $labels.machine }} is almost out of memory";
          };

          UnitFailed = {
            expression = ''node_systemd_unit_state{state="failed"} == 1'';
            summary = "{{ $labels.name }} failed on {{ $labels.machine }}";
          };
        };
      };
    };
}
