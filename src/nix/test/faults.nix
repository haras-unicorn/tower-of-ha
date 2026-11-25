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

    # NOTE: a replica follows the primary, or the primary has a replica that
    # finished its first sync; needs the toh CLI on the server
    valkey = "toh valkey valkey info replication | grep -qE '^(master_link_status:up|slave[0-9]+:.*state=online)'";
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
      # cached property, which has to go so a revive finds the new one; a
      # container can fail to stop, so the kill waits only so long and then
      # names the processes that are left and the ones that would collect
      # the init
      kills.container = ''
        # NOTE: under names of their own, because the test commands may
        # import the same modules, and the linter refuses that twice
        import os as fault_os
        import signal as fault_signal
        import time as fault_time

        def fault_kill(machine):
          with machine.nested("fault: the machine goes away at once"):
            init = machine.get_systemd_process
            namespace = fault_os.readlink(f"/proc/{init}/ns/pid")
            fault_os.kill(init, fault_signal.SIGKILL)
            deadline = fault_time.monotonic() + ${builtins.toString cfg.shutdownTimeout}
            while fault_left(namespace):
              if fault_time.monotonic() > deadline:
                left = "; ".join(fault_left(namespace))
                parents = "; ".join(fault_parents(init))
                raise Exception(
                  f"{machine.name} did not go away, left: {left}, parents: {parents}"
                )
              fault_time.sleep(1)
            machine.wait_for_shutdown()
            machine.__dict__.pop("get_systemd_process", None)

        def fault_left(namespace):
          left = []
          for pid in fault_os.listdir("/proc"):
            if not pid.isdigit():
              continue
            try:
              if fault_os.readlink(f"/proc/{pid}/ns/pid") != namespace:
                continue
              left.append(" ".join([pid] + [fault_proc(pid, name) for name in ["comm", "stat", "wchan", "stack"]]))
            except OSError:
              continue
          return left

        def fault_parents(pid):
          parents = []
          parent = fault_parent(pid)
          while parent.isdigit() and int(parent) not in [0, fault_os.getpid()]:
            parents.append(" ".join([parent] + [fault_proc(parent, name) for name in ["stat", "wchan"]]))
            parent = fault_parent(parent)
          return parents

        def fault_parent(pid):
          fields = fault_proc(pid, "stat").rsplit(")", 1)[-1].split()
          return fields[1] if len(fields) > 1 else ""

        def fault_proc(pid, name):
          try:
            with open(f"/proc/{pid}/{name}") as entry:
              return " ".join(entry.read().split())
          except OSError as error:
            return f"({name}: {error.strerror})"
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
            of a shutdown, a failover and a revive on top of the global
            timeout
          '';
        };

        shutdownTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60;
          description = ''
            Seconds a killed container has to stop; after that the test fails
            and names the processes that are left
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
