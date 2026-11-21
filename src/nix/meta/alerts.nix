{
  self.nixosModules.meta-alerts.flake = true;
  self.nixosModules.meta-alerts.value =
    {
      lib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        alerts = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Alerts API host (via proxy)";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Alerts API port (via proxy)";
          };

          url = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = "https://${config.toh.meta.alerts.host}:${builtins.toString config.toh.meta.alerts.port}";
            defaultText = lib.literalExpression ''"https://''${config.toh.meta.alerts.host}:''${builtins.toString config.toh.meta.alerts.port}"'';
            description = ''
              Base URL of the alerts API, which speaks the API of Alertmanager
              (derived from host and port)
            '';
          };

          managers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Addresses (`host:port`) of every alert manager. Every collector
              sends its alerts to all of them, not through the proxy, so that
              the managers can send each alert once.
            '';
          };
        };
      };
    };
}
