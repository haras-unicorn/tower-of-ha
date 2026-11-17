# NOTE: do not enable NTS because time can be so far off sometimes
# that it registers certs as invalid
# TODO: enable NTS after first sync

{
  toh.lib.nixosModules.services-chronyd =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.toh.services.chronyd;
    in
    {
      options.toh.services = {
        chronyd = {
          enable = lib.mkEnableOption "Chronyd";
        };
      };

      config = lib.mkIf cfg.enable {
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
          initstepslew = {
            enabled = true;
            threshold = 1;
          };
        };

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
            while true; do
              if timedatectl | grep -q "System clock synchronized: yes"; then
                exit 0
              fi
              chronyc makestep
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
