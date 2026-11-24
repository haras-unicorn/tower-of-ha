{ inputs, ... }:

{
  self.nixosModules.services-falco.flake = true;
  self.nixosModules.services-falco.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.falco;

      # NOTE: falco arrives in nixos 26.11, so until then its package and
      # module come from unstable, which hydra builds and caches
      unstable = inputs.nixpkgs-unstable;

      job = "falco";

      matches = "falcosecurity_falco_rules_matches_total";

      # NOTE: falco exports the counter of a rule only after its first
      # match, which increase() cannot see; so a series that is new since
      # one window ago counts as a match too, but only where falco was
      # collected back then, or a restart of prometheus would repeat every
      # old match
      matchesOf = selector: ''
        max by (machine, rule_name) (
          increase(${matches}{${selector}}[${cfg.alerts.window}]) > 0
        )
        or
        max by (machine, rule_name) (
          (
            ${matches}{${selector}}
              unless ${matches}{${selector}} offset ${cfg.alerts.window}
          )
          and on (machine) (up{job="${job}"} offset ${cfg.alerts.window} == 1)
        )
      '';

      # NOTE: falco numbers its priorities from emergency (0) to debug (7),
      # and error (3) is the last one that is critical
      critical = ''priority=~"[0-3]"'';
      notCritical = ''priority!~"[0-3]"'';
    in
    {
      imports = [ "${unstable}/nixos/modules/services/security/falco.nix" ];

      options.toh.services.falco = {
        enable = lib.mkEnableOption "Falco, which watches the system calls of the machine for suspicious activity";

        port = lib.mkOption {
          type = lib.types.port;
          default = 8765;
          description = "Port of the web server of Falco, which serves its metrics.";
        };

        priority = lib.mkOption {
          type = lib.types.enum [
            "emergency"
            "alert"
            "critical"
            "error"
            "warning"
            "notice"
            "informational"
            "debug"
          ];
          default = "notice";
          description = "Lowest priority of the rules Falco loads.";
        };

        alerts.window = lib.mkOption {
          type = lib.types.str;
          default = "10m";
          description = "How long a match of a rule stays an alert.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.falco = {
          enable = true;
          package = unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.falco;
          settings = {
            inherit (cfg) priority;

            webserver = {
              enabled = true;
              listen_address = config.toh.meta.network.ip;
              listen_port = cfg.port;
              prometheus_metrics_enabled = true;
            };

            metrics = {
              enabled = true;
              # NOTE: prometheus collects the counters, so the snapshot falco
              # would log at every interval only repeats them
              output_rule = false;
            };
          };
        };

        systemd.services.falco = {
          wantedBy = [ "toh-network-online.target" ];
          after = [ "toh-network-online.target" ];
          requires = [ "toh-network-online.target" ];
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        toh.meta.metrics.targets.${job}.port = cfg.port;

        toh.meta.metrics.alerts = {
          FalcoCriticalRuleMatched = {
            expression = matchesOf critical;
            severity = "critical";
            summary = "Falco saw {{ $labels.rule_name }} on {{ $labels.machine }}";
          };

          FalcoRuleMatched = {
            expression = matchesOf notCritical;
            summary = "Falco saw {{ $labels.rule_name }} on {{ $labels.machine }}";
          };
        };
      };
    };
}
