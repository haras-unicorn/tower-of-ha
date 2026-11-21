{
  self.nixosModules.meta-metrics.flake = true;
  self.nixosModules.meta-metrics.value =
    {
      lib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        metrics = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Metrics query host (via proxy)";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Metrics query port (via proxy)";
          };

          url = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = "https://${config.toh.meta.metrics.host}:${builtins.toString config.toh.meta.metrics.port}";
            defaultText = lib.literalExpression ''"https://''${config.toh.meta.metrics.host}:''${builtins.toString config.toh.meta.metrics.port}"'';
            description = ''
              Base URL of the metrics query API, which speaks the query API of
              Prometheus (derived from host and port)
            '';
          };

          targets = lib.mkOption {
            default = { };
            description = ''
              Metrics that can be collected from this machine, by name. Every
              collector of the cluster collects every target of every machine,
              at the address of the machine.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  port = lib.mkOption {
                    type = lib.types.port;
                    description = "Port the metrics are served on";
                  };

                  path = lib.mkOption {
                    type = lib.types.str;
                    default = "/metrics";
                    description = "Path the metrics are served on";
                  };
                };
              }
            );
          };

          alerts = lib.mkOption {
            default = { };
            description = ''
              Alerts, by name, which has to be a valid metric name. They hold
              for the whole cluster: every machine declares the alerts of its
              services, and the collectors evaluate the alerts of every
              machine on the metrics of the whole cluster.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  expression = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      Query in the language of Prometheus. The alert fires
                      once for every series it returns.
                    '';
                  };

                  for = lib.mkOption {
                    type = lib.types.str;
                    default = "1m";
                    description = ''
                      How long the query has to return a series before the
                      alert fires.
                    '';
                  };

                  severity = lib.mkOption {
                    type = lib.types.enum [
                      "warning"
                      "critical"
                    ];
                    default = "warning";
                    description = "How bad it is when the alert fires";
                  };

                  summary = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      What went wrong, for the person who gets the alert. It
                      may use the labels of the series, like
                      `{{ $labels.machine }}`.
                    '';
                  };
                };
              }
            );
          };
        };
      };
    };
}
