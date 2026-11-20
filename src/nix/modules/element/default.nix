{
  self.nixosModules.services-element.flake = true;
  self.nixosModules.services-element.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.element;

      # NOTE: nixpkgs merges this into the sample config of Element, which
      # points at matrix.org and the services of Element, so the keys that
      # would reach them are set to null, which Element reads as not set
      element = pkgs.element-web.override {
        conf = {
          default_server_config = {
            "m.homeserver".base_url = config.toh.meta.chat.url;
            "m.identity_server" = null;
          };
          disable_custom_urls = true;
          disable_guests = true;
          disable_3pid_login = true;
          integrations_ui_url = null;
          integrations_rest_url = null;
          integrations_widgets_urls = null;
          room_directory.servers = [ ];
          jitsi = null;
          element_call.disable = true;
          mobile_guide_toast = false;
          setting_defaults = {
            "UIFeature.identityServer" = false;
            "UIFeature.voip" = false;
            "UIFeature.widgets" = false;
            "UIFeature.feedback" = false;
          };
        };
      };
    in
    {
      options.toh.services = {
        element = {
          enable = lib.mkEnableOption "Element, the web client for the chat";

          port = lib.mkOption {
            type = lib.types.port;
            default = 8093;
            description = "Port of the web server that serves Element.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.static-web-server = {
          enable = true;
          listen = "${config.toh.meta.network.ip}:${builtins.toString cfg.port}";
          root = element;
          configuration.general = {
            health = true;
            security-headers = true;
          };
        };

        # NOTE: the socket starts before the network has its address, so it
        # binds to an address the machine does not have yet
        systemd.sockets.static-web-server.socketConfig.FreeBind = true;

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        toh.meta.services.element = {
          endpoint.http.port = cfg.port;
          health.endpoint.http = {
            port = cfg.port;
            path = "/health";
          };
        };
      };
    };
}
