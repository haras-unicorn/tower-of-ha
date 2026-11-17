{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-chronyd = pkgs.tohPackages.testers.runToHTest {
        name = "services-chronyd";
        toh.test.ntp.enable = true;
        nodes.machine = {
          toh.services.chronyd.enable = true;

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
            machine.succeed("chronyc sources | grep -q '${nodes.ntp.toh.meta.network.ip}'")

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
