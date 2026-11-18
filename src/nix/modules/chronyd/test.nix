{ selfLib, ... }:

let
  machine = {
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
in
{
  self.nixosTests.services-chronyd = selfLib.test.makeNixosTest {
    toh.test.ntp.enable = true;

    containers.machine = machine;

    toh.test.commands.suffix =
      { nodes, ... }:
      ''
        machine.succeed("which chronyd")
        machine.succeed("which chronyc")
        machine.wait_for_unit("toh-time-synchronized.target", timeout=60)
        machine.wait_until_succeeds("chronyc -n sources | grep -q '${nodes.ntp.toh.meta.network.ip}'", timeout=60)

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
        machine.wait_until_fails("systemctl is-active toh-time-synchronized.target", timeout=60)
        machine.wait_until_fails("systemctl is-active time-dependant.service", timeout=60)
        machine.wait_until_succeeds("systemctl is-active chronyd-sync-wait.service", timeout=60)
        machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
        machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)

        # NOTE: failure
        machine.succeed("pkill -sigkill chronyd")
        machine.wait_until_fails("systemctl is-active toh-time-synchronized.target", timeout=60)
        machine.wait_until_fails("systemctl is-active time-dependant.service", timeout=60)
        machine.succeed("systemctl start chronyd")
        machine.wait_until_succeeds("systemctl is-active chronyd-sync-wait.service", timeout=60)
        machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
        machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)
      '';
  };

  # NOTE: containers share the clock of the host, so the checked test runs
  # chrony with -x; this test sets the clock of a vm and stays out of the
  # checks because it is slower and needs kvm
  self.nixosTests.services-chronyd-clock =
    selfLib.test.makeNixosTest {
      toh.test.kind = "vm";
      toh.test.ntp.enable = true;

      nodes.machine = machine;

      toh.test.commands.suffix = ''
        skew_seconds = 3600
        tolerance_seconds = 5

        def clock_offset():
          return int(machine.succeed("date +%s")) - int(ntp.succeed("date +%s"))

        machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)

        machine.succeed("systemctl stop chronyd")
        machine.succeed(f"date -s @$(( $(date +%s) + {skew_seconds} ))")
        offset = clock_offset()
        assert offset > skew_seconds - tolerance_seconds, f"the clock did not move: {offset}s off"

        machine.succeed("systemctl start chronyd")
        machine.wait_until_succeeds("systemctl is-active toh-time-synchronized.target", timeout=60)
        machine.wait_until_succeeds("systemctl is-active time-dependant.service", timeout=60)
        offset = clock_offset()
        assert abs(offset) < tolerance_seconds, f"chrony did not set the clock: {offset}s off"
      '';
    }
    // {
      flake = false;
    };
}
