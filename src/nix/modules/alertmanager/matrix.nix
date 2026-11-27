{
  self.nixosModules.services-alertmanager-matrix.flake = true;
  self.nixosModules.services-alertmanager-matrix.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.alertmanager.matrix;

      enabled = config.toh.services.alertmanager.enable && cfg.enable;

      name = "alertmanager-matrix";
      app = "alerts";

      chat = config.toh.meta.chat;
      chatUser = chat.users.${app};

      runtimeDirectory = "/run/${name}";
      configFile = "${runtimeDirectory}/config.json";

      settings = {
        output = configFile;
        url = chat.url;
        user = chatUser.name;
        userId = "@${chatUser.name}:${chat.serverName}";
        password = chatUser.password;
        room = chatUser.room;
        config = {
          http = {
            address = config.toh.meta.network.ip;
            inherit (cfg) port;
            alerts-path-prefix = cfg.alertsPath;
            metrics-path = cfg.metricsPath;
            metrics-enabled = true;
          };
          matrix.homeserver-url = chat.url;
          templating = {
            firing-template = ''
              <p><strong>{{ .Alert.Status | ToUpper }}</strong>
              {{ .Alert.Labels.alertname }} ({{ .Alert.Labels.severity }}):
              {{ .Alert.Annotations.summary }}</p>
            '';
            resolved-template = ''
              <p><strong>RESOLVED</strong> {{ .Alert.Labels.alertname }}:
              {{ .Alert.Annotations.summary }}</p>
            '';
          };
        };
      };

      prepare = pkgs.tohPackages.writeNushellApplication {
        name = "${name}-prepare";
        text = pkgs.harasPackages.renderMustacheText {
          name = "${name}-prepare-text";
          text = builtins.readFile ./matrix.nu;
          vars = {
            TOH_ALERTMANAGER_MATRIX = builtins.toJSON (settings // { inherit (cfg) roomName; });
          };
        };
      };
    in
    {
      options.toh.services.alertmanager.matrix = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether Alertmanager posts the alerts into the room of the chat app
            `alerts`, through a bridge on every Alertmanager machine.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9095;
          description = "Port of the bridge that Alertmanager sends the alerts to, behind the proxy.";
        };

        alertsPath = lib.mkOption {
          type = lib.types.str;
          default = "/alerts";
          description = "Path of the bridge that takes the alerts.";
        };

        metricsPath = lib.mkOption {
          type = lib.types.str;
          default = "/metrics";
          description = "Path of the metrics of the bridge, which is also its health check.";
        };

        roomName = lib.mkOption {
          type = lib.types.str;
          default = "toh";
          description = "Name the bridge knows the room by, in the path Alertmanager sends to.";
        };

        invite = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "@me:matrix.example.com" ];
          description = "Chat users invited into the room of the alerts, so that they get them.";
        };

        retrySeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = ''
            Seconds between starts of the bridge, which fails until the chat
            has made its user and room. A start logs in only once the room
            is there.
          '';
        };
      };

      config = lib.mkIf enabled {
        users.groups.${name} = { };
        users.users.${name} = {
          isSystemUser = true;
          group = name;
        };

        toh.meta.chat.apps.${app} = {
          user = name;
          group = name;
          inherit (cfg) invite;
        };

        systemd.services.${name} = {
          description = "Bridge from Alertmanager to the chat";
          wantedBy = [ "toh-network-online.target" ];
          after = [ "toh-network-online.target" ];
          requires = [ "toh-network-online.target" ];
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig = {
            User = name;
            Group = name;
            RuntimeDirectory = name;
            RuntimeDirectoryMode = "0700";
            ExecStartPre = lib.getExe prepare;
            ExecStart = "${lib.getExe pkgs.matrix-alertmanager-receiver} --config-path ${configFile}";
            Restart = "always";
            RestartSec = cfg.retrySeconds;
          };
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        toh.meta.services.${name} = {
          endpoint.http.port = cfg.port;
          health.endpoint.http = {
            inherit (cfg) port;
            path = cfg.metricsPath;
          };
        };

        toh.meta.metrics.targets.${name} = {
          inherit (cfg) port;
          path = cfg.metricsPath;
        };

        toh.pki.installCa = true;
      };
    };
}
