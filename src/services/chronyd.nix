{ self, ... }:

# NOTE: do not enable NTS because time can be so far off sometimes
# that it registers certs as invalid
# TODO: enable NTS after first sync

{
  flake.nixosModules.services-chronyd =
    { lib, pkgs, ... }:
    {
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

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-chronyd = pkgs.tohPackages.testers.runToHTest {
        name = "services-chronyd";
        toh.test.ntp.enable = true;
        nodes.machine = {
          imports = [ self.nixosModules.services-chronyd ];

          systemd.services.time-dependant = {
            description = "Service dependant on time synchronization";
            wantedBy = [ "toh-time-synchronized.target" ];
            requires = [ "toh-time-synchronized.target" ];
            after = [ "toh-time-synchronized.target" ];
            script = ''
              while true; do
                sleep 10
                timedatectl
              done
            '';
          };
        };
        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.succeed("which chronyd")
            machine.succeed("which chronyc")
            machine.wait_for_unit("toh-time-synchronized.target", timeout=60)
            machine.succeed("chronyc sources | grep -q '${nodes.ntp.toh.host.ip}'")

            # NOTE: expected stop
            machine.succeed("systemctl stop chronyd")
            machine.fail("systemctl is-active toh-time-synchronized.target")
            machine.fail("systemctl is-active time-dependant.service")
            machine.succeed("systemctl start chronyd")
            machine.wait_until_succeeds("systemctl is-active chronyd-sync-wait.service", timeout=60)
            machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
            machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)

            # NOTE: unexpected stop
            machine.succeed("pkill -sigterm chronyd")
            machine.fail("systemctl is-active toh-time-synchronized.target")
            machine.fail("systemctl is-active time-dependant.service")
            machine.wait_until_succeeds("systemctl is-active chronyd-sync-wait.service", timeout=60)
            machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
            machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)

            # NOTE: failure
            machine.succeed("pkill -sigkill chronyd")
            machine.fail("systemctl is-active toh-time-synchronized.target")
            machine.fail("systemctl is-active time-dependant.service")
            machine.succeed("systemctl start chronyd")
            machine.wait_until_succeeds("systemctl is-active chronyd-sync-wait.service", timeout=60)
            machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
            machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)
          '';
      };
    };
}
