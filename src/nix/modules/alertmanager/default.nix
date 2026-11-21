{ selfLib, ... }:

{
  self.nixosModules.services-alertmanager.flake = true;
  self.nixosModules.services-alertmanager.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.alertmanager;

      anyMachines = selfLib.cluster.anyServiceMachines config "alertmanager";

      ip = config.toh.meta.network.ip;

      # NOTE: the nixpkgs module joins the other managers on this port and
      # has no option for it
      clusterPort = 9094;

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.alertmanager.endpoint;

      receiverAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.alertmanager-matrix.endpoint;

      receiver =
        if cfg.matrix.enable then
          {
            name = "matrix";
            webhook_configs = [
              {
                url = "https://${receiverAttrs.host}:${builtins.toString receiverAttrs.port}${cfg.matrix.alertsPath}/${cfg.matrix.roomName}";
                send_resolved = true;
              }
            ];
          }
        else
          { name = "nobody"; };
    in
    {
      options.toh.services.alertmanager = {
        enable = lib.mkEnableOption "Alertmanager, which sends each alert of the cluster once";

        port = lib.mkOption {
          type = lib.types.port;
          default = 9093;
          description = "Port of the API and UI of Alertmanager.";
        };

        groupWait = lib.mkOption {
          type = lib.types.str;
          default = "30s";
          description = "How long the first alert of a group waits for others to send them together.";
        };

        groupInterval = lib.mkOption {
          type = lib.types.str;
          default = "5m";
          description = "How long a group waits before it sends alerts that joined it.";
        };

        repeatInterval = lib.mkOption {
          type = lib.types.str;
          default = "4h";
          description = "How long before an alert that still fires is sent again.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.alerts = {
            host = proxyAttrs.host;
            port = proxyAttrs.port;
            managers = builtins.map (
              machine:
              "${machine.meta.network.ip}:${builtins.toString machine.config.toh.services.alertmanager.port}"
            ) (selfLib.cluster.serviceMachines config "alertmanager");
          };
        })
        (lib.mkIf cfg.enable {
          services.prometheus.alertmanager = {
            enable = true;
            listenAddress = ip;
            inherit (cfg) port;
            clusterPeers = builtins.map (machine: machine.meta.network.ip) (
              selfLib.cluster.otherServiceMachines config "alertmanager"
            );
            extraFlags = [ "--cluster.listen-address=${ip}:${builtins.toString clusterPort}" ];
            configuration = {
              route = {
                receiver = receiver.name;
                group_by = [ "alertname" ];
                group_wait = cfg.groupWait;
                group_interval = cfg.groupInterval;
                repeat_interval = cfg.repeatInterval;
              };
              receivers = [ receiver ];
            };
          };

          systemd.services.alertmanager = {
            wantedBy = [ "toh-network-online.target" ];
            after = [ "toh-network-online.target" ];
            requires = [ "toh-network-online.target" ];
          };

          networking.firewall = {
            allowedTCPPorts = [
              cfg.port
              clusterPort
            ];
            allowedUDPPorts = [ clusterPort ];
          };

          toh.meta.services.alertmanager = {
            endpoint.http.port = cfg.port;
            health.endpoint.http = {
              port = cfg.port;
              path = "/-/healthy";
            };
          };

          toh.meta.metrics.targets.alertmanager.port = cfg.port;

          toh.pki.installCa = true;
        })
      ];
    };
}
