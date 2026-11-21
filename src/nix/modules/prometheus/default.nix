{ selfLib, ... }:

{
  self.nixosModules.services-prometheus.flake = true;
  self.nixosModules.services-prometheus.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.prometheus;

      anyMachines = selfLib.cluster.anyServiceMachines config "prometheus";
      prometheusMachines = selfLib.cluster.serviceMachines config "prometheus";

      machineList = config.toh.meta.cluster.machineList;
      ip = config.toh.meta.network.ip;

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.thanos-query.endpoint;

      # NOTE: every copy of Prometheus marks its series with its own value of
      # this label, Thanos Query merges the copies along it, and alerts lose
      # it, so that the alert managers see one alert from all copies
      replicaLabel = "replica";

      address = port: "${ip}:${builtins.toString port}";

      targetNames = lib.unique (
        builtins.concatMap (machine: builtins.attrNames machine.meta.metrics.targets) machineList
      );

      makeScrapeConfig =
        name:
        let
          machinesWithTarget = builtins.filter (machine: machine.meta.metrics.targets ? ${name}) machineList;
        in
        {
          job_name = name;
          static_configs = builtins.map (
            machine:
            let
              target = machine.meta.metrics.targets.${name};
            in
            {
              targets = [ "${machine.meta.network.ip}:${builtins.toString target.port}" ];
              labels = {
                machine = machine.name;
                __metrics_path__ = target.path;
              };
            }
          ) machinesWithTarget;
        };

      alerts = builtins.foldl' (alerts: machine: alerts // machine.meta.metrics.alerts) { } machineList;

      rules = pkgs.writeText "toh-alerts.rules" (
        builtins.toJSON {
          groups = [
            {
              name = "toh";
              rules = lib.mapAttrsToList (name: alert: {
                alert = name;
                expr = alert.expression;
                inherit (alert) for;
                labels.severity = alert.severity;
                annotations.summary = alert.summary;
              }) alerts;
            }
          ];
        }
      );

      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = cfg.evaluationInterval;
        external_labels.${replicaLabel} = config.toh.meta.machine.name;
      };

      managers = config.toh.meta.alerts.managers;

      prometheusConfig = {
        global = globalConfig;
        scrape_configs = builtins.map makeScrapeConfig targetNames;
        rule_files = [ rules ];
        alerting = {
          alert_relabel_configs = [
            {
              action = "labeldrop";
              regex = replicaLabel;
            }
          ];
          alertmanagers = lib.optional (managers != [ ]) {
            static_configs = [ { targets = managers; } ];
          };
        };
      };

      networkDependencies = {
        wantedBy = [ "toh-network-online.target" ];
        after = [ "toh-network-online.target" ];
        requires = [ "toh-network-online.target" ];
      };
    in
    {
      options.toh.services.prometheus = {
        enable = lib.mkEnableOption "Prometheus, with Thanos Query in front of all copies";

        port = lib.mkOption {
          type = lib.types.port;
          default = 9090;
          description = "Port of Prometheus.";
        };

        scrapeInterval = lib.mkOption {
          type = lib.types.str;
          default = "15s";
          description = "Time between two collections of a target.";
        };

        evaluationInterval = lib.mkOption {
          type = lib.types.str;
          default = "15s";
          description = "Time between two evaluations of the alerts.";
        };

        retention = lib.mkOption {
          type = lib.types.str;
          default = "15d";
          description = "How long each copy keeps what it collected.";
        };

        alerts.targetDownFor = lib.mkOption {
          type = lib.types.str;
          default = "2m";
          description = "How long a target may not answer before it is an alert.";
        };

        thanos = {
          sidecarGrpcPort = lib.mkOption {
            type = lib.types.port;
            default = 10901;
            description = "Port of the Thanos sidecar that Thanos Query reads each copy through.";
          };

          sidecarHttpPort = lib.mkOption {
            type = lib.types.port;
            default = 10902;
            description = "Port of the metrics of the Thanos sidecar.";
          };

          queryGrpcPort = lib.mkOption {
            type = lib.types.port;
            default = 10903;
            description = "Port of the gRPC API of Thanos Query.";
          };

          queryHttpPort = lib.mkOption {
            type = lib.types.port;
            default = 10904;
            description = "Port of the query API and UI of Thanos Query, behind the proxy.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.metrics = {
            host = proxyAttrs.host;
            port = proxyAttrs.port;
          };
        })
        (lib.mkIf cfg.enable {
          services.prometheus = {
            enable = true;
            listenAddress = ip;
            inherit (cfg) port;
            retentionTime = cfg.retention;
            # NOTE: the Thanos sidecar of nixpkgs checks for external labels
            # here, though the configuration below is the one that counts
            inherit globalConfig;
            # NOTE: the whole configuration as text, because the nixpkgs
            # module cannot set the relabeling of alerts
            configText = builtins.toJSON prometheusConfig;
          };

          services.thanos.sidecar = {
            enable = true;
            grpc-address = address cfg.thanos.sidecarGrpcPort;
            http-address = address cfg.thanos.sidecarHttpPort;
            prometheus.url = "http://${address cfg.port}";
          };

          services.thanos.query = {
            enable = true;
            grpc-address = address cfg.thanos.queryGrpcPort;
            http-address = address cfg.thanos.queryHttpPort;
            endpoints = builtins.map (
              machine:
              "${machine.meta.network.ip}:${builtins.toString machine.config.toh.services.prometheus.thanos.sidecarGrpcPort}"
            ) prometheusMachines;
            query.replica-labels = [ replicaLabel ];
          };

          systemd.services.prometheus = networkDependencies;
          systemd.services.thanos-sidecar = networkDependencies;
          systemd.services.thanos-query = networkDependencies;

          networking.firewall.allowedTCPPorts = [
            cfg.port
            cfg.thanos.sidecarGrpcPort
            cfg.thanos.sidecarHttpPort
            cfg.thanos.queryHttpPort
          ];

          toh.meta.services.thanos-query = {
            endpoint.http.port = cfg.thanos.queryHttpPort;
            health.endpoint.http = {
              port = cfg.thanos.queryHttpPort;
              path = "/-/ready";
            };
          };

          toh.meta.metrics.targets = {
            prometheus.port = cfg.port;
            thanos-sidecar.port = cfg.thanos.sidecarHttpPort;
            thanos-query.port = cfg.thanos.queryHttpPort;
          };

          toh.meta.metrics.alerts.TargetDown = {
            expression = "up == 0";
            for = cfg.alerts.targetDownFor;
            summary = "{{ $labels.job }} on {{ $labels.machine }} does not answer";
          };
        })
      ];
    };
}
