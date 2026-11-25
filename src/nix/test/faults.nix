# NOTE: the faults of step 8 as python helpers, so every test breaks its
# machines the same way; what a test checks after a fault is in
# docs/design.md, under the decisions of 2026-11-25

{
  # NOTE: commands that succeed on a server once the service can lose any one
  # server, for the redundant option of the contracts, joined with && where
  # an implementation keeps its data in more than one of these
  self.lib.test.redundant = {
    # NOTE: only the synchronous standby may take over, and Patroni names it
    # a little after the cluster starts
    patroni = "patronictl list | grep 'Sync Standby' | grep -q streaming";

    # NOTE: every placement group is clean again, so all its copies are
    # there, and a metadata server waits to take over
    cephfs = "ceph pg stat | grep -qE '^[0-9]+ pgs: [0-9]+ active[+]clean;' && ceph mds stat | grep -q up:standby";
  };

  self.lib.test.testModules.faults =
    { lib, config, ... }:
    let
      cfg = config.toh.test.faults;

      kills.vm = ''
        def fault_kill(machine):
          with machine.nested("fault: the machine goes away at once"):
            machine.crash()
      '';

      # NOTE: containers have no crash() in the test driver, so the init of
      # the container gets SIGKILL from outside, which looks like a lost
      # machine to the others; the driver keeps the pid of that init in a
      # cached property, which has to go so a revive finds the new one
      kills.container = ''
        # NOTE: under names of their own, because the test commands may
        # import the same modules, and the linter refuses that twice
        import os as fault_os
        import signal as fault_signal

        def fault_kill(machine):
          with machine.nested("fault: the machine goes away at once"):
            fault_os.kill(machine.get_systemd_process, fault_signal.SIGKILL)
            machine.wait_for_shutdown()
            machine.__dict__.pop("get_systemd_process", None)
      '';
    in
    {
      options.toh.test.faults = {
        failoverTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 120;
          description = ''
            Seconds a service has to answer again after a fault, without
            anyone doing anything; a test of a service sets its own
          '';
        };

        kills = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          description = ''
            Machines the test kills and revives, each of which gets the time
            of a failover and a revive on top of the global timeout
          '';
        };

        reviveTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 300;
          description = ''
            Seconds a machine has, after it comes back, to boot and start its
            services again
          '';
        };
      };

      config.toh.test.commands.helpers = [
        kills.${config.toh.test.kind}
        ''
          def fault_revive(machine):
            with machine.nested("fault: the machine comes back"):
              machine.start()

          # NOTE: every server goes away once, so the one that takes the
          # writes does too, whichever it is; redundant succeeds on a server
          # once the service can lose any one server, and write and holds
          # give the commands that write a value and that succeed only while
          # the value is still there, which the client runs, or the reader
          # where a client could answer from what it holds itself; a client
          # that may only read has no write, and holds then checks what was
          # there before the faults, with the value None; a test without a
          # client of its own passes None, and then one server that stays
          # writes and another that stays checks
          def fault_kill_each(client, servers, target, redundant, write, holds, reader=None):
            written = [] if write else [None]
            for server in servers:
              staying = [other for other in servers if other is not server]
              writer = client or staying[0]
              checker = reader or client or staying[-1]
              for living in servers:
                living.wait_until_succeeds(redundant, timeout=${builtins.toString cfg.reviveTimeout})
              before = f"before-{server.name}"
              if write:
                writer.succeed(write(before))
                written.append(before)
              fault_kill(server)
              after = f"after-{server.name}"
              if write:
                writer.wait_until_succeeds(write(after), timeout=${builtins.toString cfg.failoverTimeout})
                written.append(after)
              for value in written:
                checker.wait_until_succeeds(holds(value), timeout=${builtins.toString cfg.failoverTimeout})
              fault_revive(server)
              server.wait_until_succeeds(
                f"systemctl is-active {target}", timeout=${builtins.toString cfg.reviveTimeout}
              )
        ''
      ];
    };
}
