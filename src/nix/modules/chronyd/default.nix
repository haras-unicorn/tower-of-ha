# NOTE: do not enable NTS because time can be so far off sometimes
# that it registers certs as invalid
# TODO: enable NTS after first sync

{
  self.nixosModules.services-chronyd.flake = true;
  self.nixosModules.services-chronyd.value =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.toh.services.chronyd;

      maxCorrection = builtins.toString config.services.chrony.initstepslew.threshold;

      # NOTE: a machine that serves time keeps to its upstream servers, and
      # the others take time from the machines that serve it
      clusterServers = lib.optionals (!cfg.serve) config.toh.meta.time.servers;

      subnet = config.toh.meta.network.subnet;

      # NOTE: the well-known NTP port
      ntpPort = 123;
    in
    {
      options.toh.services = {
        chronyd = {
          enable = lib.mkEnableOption "Chronyd";

          serve = lib.mkEnableOption "serving time to the network of the cluster";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.meta.time.serve = cfg.serve;

        services.timesyncd.enable = false;

        networking.timeServers = [
          # Google
          "216.239.35.0"
          "216.239.35.4"
          "216.239.35.8"
          "216.239.35.12"

          # Cloudflare
          "162.159.200.1"
          "162.159.200.123"
        ];

        services.chrony = {
          enable = true;
          servers = lib.mkIf (clusterServers != [ ]) (lib.mkForce clusterServers);
          initstepslew = {
            enabled = true;
            threshold = 1;
          };
          extraConfig = lib.mkIf cfg.serve ''
            allow ${subnet.ip}/${builtins.toString subnet.bits}
          '';
        };

        networking.firewall.allowedUDPPorts = lib.mkIf cfg.serve [ ntpPort ];

        systemd.services.chronyd.after = [ "network-online.target" ];
        systemd.services.chronyd.requires = [ "network-online.target" ];
        systemd.services.chronyd.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        systemd.services.chronyd-sync-wait = {
          description = "Wait for synchronization from chrony";
          after = [ "chronyd.service" ];
          bindsTo = [ "chronyd.service" ];
          wantedBy = [ "chronyd.service" ];
          path = [ pkgs.chrony ];
          script = ''
            until chronyc waitsync 1 ${maxCorrection}; do
              chronyc makestep || echo "Could not step the clock, chrony slews it"
              sleep 10
            done
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
          };
        };

        systemd.targets.toh-time-synchronized = {
          bindsTo = [
            "chronyd.service"
            "chronyd-sync-wait.service"
          ];
          wantedBy = [ "chronyd.service" ];
          after = [
            "chronyd.service"
            "chronyd-sync-wait.service"
          ];
        };

        programs.rust-motd.settings = {
          service_status = {
            Chrony = "chronyd";
          };
        };
      };
    };
}
