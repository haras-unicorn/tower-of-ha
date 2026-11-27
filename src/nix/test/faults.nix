# NOTE: the faults of step 8 as python helpers, so every test breaks its
# machines the same way; what a test checks after a fault is in
# docs/design.md, under the decisions of 2026-11-25

{ lib, selfLib, ... }:

{
  # NOTE: the faults fault_each makes, in the order it makes them
  self.lib.test.faultKinds = [
    "kill"
    "split"
    "freeze"
  ];

  # NOTE: test modules that run fault_each, by test name; every one becomes
  # a test without faults, the happy path, and a test per fault, like
  # contracts-share-samba-split, so a failure shows up without waiting for
  # the other faults, and one fault cannot leave something behind that
  # breaks the next
  self.lib.test.faultTests = { };

  self.nixosTests = lib.concatMapAttrs (
    name: module:
    {
      ${name} = selfLib.test.makeNixosTest {
        imports = [ module ];
        toh.test.tier = 1;
        toh.test.faults.kinds = [ ];
      };
    }
    // builtins.listToAttrs (
      builtins.map (kind: {
        name = "${name}-${kind}";
        value = selfLib.test.makeNixosTest {
          imports = [ module ];
          toh.test.tier = 2;
          toh.test.faults.kinds = [ kind ];
        };
      }) selfLib.test.faultKinds
    )
  ) selfLib.test.faultTests;

  # NOTE: commands that succeed on a server once the service can lose any one
  # server, for the redundant option of the contracts, joined with && where
  # an implementation keeps its data in more than one of these
  self.lib.test.redundant = {
    # NOTE: only the synchronous standby may take over, and Patroni names it
    # a little after the cluster starts; in strict synchronous mode the one
    # that takes over commits nothing until another replica streams from it,
    # so every replica streams, and not one that still rewinds after a fault
    patroni = "patronictl list --format json | jq -e 'any(.[]; .Role == \"Sync Standby\" and .State == \"streaming\") and all(.[]; .Role == \"Leader\" or .State == \"streaming\")'";

    # NOTE: every monitor is in the quorum again, every placement group is
    # clean again, so all its copies are there, and a metadata server waits
    # to take over; a monitor can take a minute after a split to join, and
    # without it losing one more monitor loses the quorum
    cephfs = "ceph quorum_status | jq -e '(.quorum | length) == (.monmap.mons | length)' && ceph pg stat | grep -qE '^[0-9]+ pgs: [0-9]+ active[+]clean;' && ceph mds stat | grep -q up:standby";

    # NOTE: a replica follows the primary, or the primary has a replica that
    # finished its first sync; needs the toh CLI on the server
    valkey = "toh valkey valkey info replication | grep -qE '^(master_link_status:up|slave[0-9]+:.*state=online)'";
  };

  # NOTE: seconds a service waits on purpose before it takes over, read from
  # the machines of a test, for the failoverDelay option of the faults
  self.lib.test.failoverDelay = {
    # NOTE: the monitors wait out their grace for a silent metadata server,
    # then the new one waits for the mount of the machine that went away
    cephfs =
      machines:
      let
        delays = builtins.map (
          machine:
          let
            cephfs = machine.toh.services.cephfs;
          in
          if cephfs.enable then cephfs.monitorDownGrace + cephfs.reconnectTimeout else 0
        ) (builtins.attrValues machines);
      in
      builtins.foldl' (longest: delay: if delay > longest then delay else longest) 0 delays;
  };

  self.lib.test.testModules.faults =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.faults;

      failoverTime = builtins.toString (cfg.failoverTimeout + cfg.failoverDelay);

      reportUnits = lib.concatMapStrings (unit: " --unit '${unit}'") cfg.reportUnits;

      # NOTE: tests that build their own network, like the VPN tests, give
      # their machines no address of the test network, and cannot split
      addresses =
        if config.toh.test.network.enable then
          builtins.mapAttrs (_: machine: machine.toh.meta.network.ip) machines
        else
          { };

      # NOTE: under names of their own, because the test commands may import
      # the same modules, and the linter refuses that twice
      imports = ''
        import json as fault_json
        import time as fault_time
      '';

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
        def fault_kill(machine):
          with machine.nested("fault: the machine goes away at once"):
            init = machine.get_systemd_process
            namespace = fault_namespace(machine)
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
          return [
            " ".join([str(pid)] + [fault_proc(pid, name) for name in ["comm", "stat", "wchan", "stack"]])
            for pid in fault_pids(namespace)
          ]

        def fault_parents(pid):
          parents = []
          parent = fault_parent(pid)
          while parent.isdigit() and int(parent) not in [0, fault_os.getpid()]:
            parents.append(" ".join([parent] + [fault_proc(parent, name) for name in ["stat", "wchan"]]))
            parent = fault_parent(parent)
          return parents

        def fault_parent(pid):
          fields = fault_stat(pid)
          return fields[1] if len(fields) > 1 else ""
      '';

      freezes.vm = ''
        def fault_freeze(machine):
          with machine.nested("fault: the machine stops, like in a long pause"):
            machine.send_monitor_command("stop")

        def fault_thaw(machine):
          with machine.nested("fault: the machine runs again"):
            machine.send_monitor_command("cont")
      '';

      # NOTE: a container has no monitor to pause it, so every process of it
      # gets SIGSTOP from outside until none of them runs, because a process
      # may fork while the others stop; zombies cannot stop and do not run; a
      # process that waits in the kernel stops only once it leaves it, which
      # one that waits on a FUSE mount whose daemon stopped never does, so
      # once it got its SIGSTOP it counts as stopped, because it stops before
      # it runs again; a freeze that still finds processes running after
      # freezeTimeout fails and names them
      freezes.container = ''
        def fault_freeze(machine):
          with machine.nested("fault: the machine stops, like in a long pause"):
            namespace = fault_namespace(machine)
            deadline = fault_time.monotonic() + ${builtins.toString cfg.freezeTimeout}
            signaled = set()
            running = fault_running(namespace, signaled)
            while running:
              if fault_time.monotonic() > deadline:
                left = "; ".join(
                  " ".join([str(pid)] + [fault_proc(pid, name) for name in ["comm", "stat", "wchan"]])
                  for pid in running
                )
                raise Exception(f"{machine.name} did not stop, running: {left}")
              fault_signal_all(running, fault_signal.SIGSTOP)
              signaled.update(running)
              fault_time.sleep(0.1)
              running = fault_running(namespace, signaled)

        def fault_thaw(machine):
          with machine.nested("fault: the machine runs again"):
            fault_signal_all(fault_pids(fault_namespace(machine)), fault_signal.SIGCONT)

        def fault_running(namespace, signaled):
          return [
            pid for pid in fault_pids(namespace)
            if not fault_stopped(fault_state(pid), pid in signaled)
          ]

        def fault_stopped(state, signaled):
          return state in ["T", "t", "Z", "X", ""] or (state == "D" and signaled)

        def fault_signal_all(pids, signal):
          for pid in pids:
            try:
              fault_os.kill(pid, signal)
            except ProcessLookupError:
              continue

        def fault_state(pid):
          fields = fault_stat(pid)
          return fields[0] if fields else ""
      '';

      # NOTE: what the kills and freezes of containers read from /proc
      processes.container = ''
        import os as fault_os
        import signal as fault_signal

        def fault_namespace(machine):
          return fault_os.readlink(f"/proc/{machine.get_systemd_process}/ns/pid")

        def fault_pids(namespace):
          pids = []
          for pid in fault_os.listdir("/proc"):
            if not pid.isdigit():
              continue
            try:
              if fault_os.readlink(f"/proc/{pid}/ns/pid") == namespace:
                pids.append(int(pid))
            except OSError:
              continue
          return pids

        def fault_stat(pid):
          return fault_proc(pid, "stat").rsplit(")", 1)[-1].split()

        def fault_proc(pid, name):
          try:
            with open(f"/proc/{pid}/{name}") as entry:
              return " ".join(entry.read().split())
          except OSError as error:
            return f"({name}: {error.strerror})"

        def fault_stuck(machine):
          init = machine.get_systemd_process
          return [
            " ".join([str(pid)] + fault_stat(pid)[:1] + [fault_proc(pid, name) for name in ["comm", "wchan", "stack"]])
            for pid in fault_pids(fault_namespace(machine))
            if pid == init or fault_stat(pid)[:1] == ["D"] or "fuse" in fault_proc(pid, "wchan")
          ]
      '';

      # NOTE: the processes of a vm are inside its own kernel, out of reach
      processes.vm = ''
        def fault_stuck(machine):
          return []
      '';
    in
    {
      options.toh.test.faults = {
        kinds = lib.mkOption {
          type = lib.types.listOf (lib.types.enum selfLib.test.faultKinds);
          default = selfLib.test.faultKinds;
          description = ''
            Faults fault_each makes on every server, in this order
          '';
        };

        failoverTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 120;
          description = ''
            Seconds a service has to answer again after a fault, without
            anyone doing anything; a test of a service sets its own
          '';
        };

        failoverDelay = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          description = ''
            Seconds a service waits on purpose before it takes over, like the
            graces of CephFS, which a failover gets on top of the timeout
          '';
        };

        freezeTime = lib.mkOption {
          type = lib.types.ints.positive;
          default = 60;
          description = ''
            Seconds a frozen machine stays frozen at least, longer than the
            leases and graces of the services, so the others notice and take
            over before it runs again
          '';
        };

        freezeTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = ''
            Seconds the processes of a frozen container have to stop; after
            that the test fails and names the processes that still run
          '';
        };

        reportLines = lib.mkOption {
          type = lib.types.ints.positive;
          default = 300;
          description = ''
            Lines of the journal of every server that go into the log when a
            check after a fault fails
          '';
        };

        reportUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Units, or patterns of units, whose journal goes into the log when
            a check after a fault fails, so one that logs a lot does not
            push out the others; empty for the whole journal
          '';
        };

        reportCommands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Commands whose output goes into the log, from every server, when
            a check after a fault fails, for what the journal does not show
          '';
        };

        reportTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = ''
            Seconds a server has to give its journal for the log, so one that
            is down or frozen does not hold the test up
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

        cephfs = {
          monitorDownGrace = lib.mkOption {
            type = lib.types.ints.positive;
            default = 30;
            description = ''
              The `monitorDownGrace` of CephFS in a test with faults, shorter
              than the default, because every fault of every server waits it
              out once and a test has to fit its budget
            '';
          };

          reconnectTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 20;
            description = ''
              The `reconnectTimeout` of CephFS in a test with faults, shorter
              than the default for the same reason
            '';
          };
        };
      };

      # NOTE: the faults check that the cluster stays correct and not how
      # fast it fails over with the default timings, so a test with faults
      # shortens the graces it waits out on every fault
      config.defaults = lib.mkIf (cfg.kinds != [ ]) {
        toh.services.cephfs.monitorDownGrace = lib.mkDefault cfg.cephfs.monitorDownGrace;
        toh.services.cephfs.reconnectTimeout = lib.mkDefault cfg.cephfs.reconnectTimeout;
      };

      config.toh.test.commands.helpers = [
        imports
        processes.${config.toh.test.kind}
        kills.${config.toh.test.kind}
        freezes.${config.toh.test.kind}
        # NOTE: the JSON goes in as a JSON string, which python reads the
        # same way, so quotes in a report command cannot end it early
        ''
          fault_addresses = fault_json.loads(${builtins.toJSON (builtins.toJSON addresses)})
          fault_kinds = fault_json.loads(${builtins.toJSON (builtins.toJSON cfg.kinds)})
          fault_report_commands = fault_json.loads(${builtins.toJSON (builtins.toJSON cfg.reportCommands)})

          def fault_revive(machine):
            with machine.nested("fault: the machine comes back"):
              machine.start()

          # NOTE: the cut drops everything between the machine and the
          # others, also what is already connected, and leaves the rest of
          # the network alone, so a client may still reach both sides
          def fault_split(machine, others):
            with machine.nested("fault: the network splits the machine off"):
              machine.succeed(*fault_cut_rules("-I", others))

          def fault_join(machine, others):
            with machine.nested("fault: the network split heals"):
              machine.succeed(*fault_cut_rules("-D", others))

          def fault_cut_rules(action, others):
            rules = []
            for other in others:
              address = fault_addresses[other.name]
              rules.append(f"iptables {action} INPUT -s {address} -j DROP")
              rules.append(f"iptables {action} OUTPUT -d {address} -j DROP")
            return rules

          # NOTE: every server gets every fault once, so the one that takes
          # the writes does too, whichever it is; redundant succeeds on a
          # server once the service can lose any one server, and write and
          # holds give the commands that write a value and that succeed only
          # while the value is still there, which the client runs, or the
          # reader where a client could answer from what it holds itself; a
          # client that may only read has no write, and holds then checks
          # what was there before the faults, with the value None; a test
          # without a client of its own passes None, and then one server
          # that stays writes and another that stays checks; every value is
          # checked again at the end, once the cluster is whole, so a write
          # that a split off or frozen server took and lost later shows up;
          # every write may fail a few times, because a server that was split
          # off or frozen may still take its old role for a moment when it
          # comes back, and only what was confirmed counts; when something
          # fails, the journals of the servers go into the log
          def fault_each(client, servers, target, redundant, write, holds, reader=None):
            try:
              fault_rounds(client, servers, target, redundant, write, holds, reader)
            except Exception:
              fault_report(servers)
              raise

          def fault_rounds(client, servers, target, redundant, write, holds, reader):
            faults = {
              "kill": (lambda server, others: fault_kill(server), lambda server, others: fault_revive(server)),
              "split": (fault_split, fault_join),
              "freeze": (lambda server, others: fault_freeze(server), lambda server, others: fault_thaw(server)),
            }
            written = [] if write else [None]
            for name in fault_kinds:
              fault, heal = faults[name]
              for server in servers:
                staying = [other for other in servers if other is not server]
                writer = client or staying[0]
                checker = reader or client or staying[-1]
                fault_wait_redundant(servers, redundant)
                if write:
                  writer.wait_until_succeeds(write(f"before-{name}-{server.name}"), timeout=${failoverTime})
                  written.append(f"before-{name}-{server.name}")
                started = fault_time.monotonic()
                fault(server, staying)
                if write:
                  writer.wait_until_succeeds(write(f"during-{name}-{server.name}"), timeout=${failoverTime})
                  written.append(f"during-{name}-{server.name}")
                fault_holds(checker, holds, written)
                if name == "freeze":
                  fault_time.sleep(max(0, started + ${builtins.toString cfg.freezeTime} - fault_time.monotonic()))
                heal(server, staying)
                server.wait_until_succeeds(
                  f"systemctl is-active {target}", timeout=${builtins.toString cfg.reviveTimeout}
                )
                if write:
                  writer.wait_until_succeeds(write(f"after-{name}-{server.name}"), timeout=${failoverTime})
                  written.append(f"after-{name}-{server.name}")
                fault_holds(checker, holds, written)
            fault_wait_redundant(servers, redundant)
            fault_holds(reader or client or servers[-1], holds, written)

          def fault_wait_redundant(servers, redundant):
            for server in servers:
              server.wait_until_succeeds(redundant, timeout=${builtins.toString cfg.reviveTimeout})

          def fault_holds(checker, holds, written):
            for value in written:
              checker.wait_until_succeeds(holds(value), timeout=${failoverTime})

          # NOTE: the console of a container reaches the log only when it
          # stops, so the journal of a server that still runs is read here; a
          # server that is down or frozen does not answer in time; init and
          # the processes that wait in the kernel, like on a mount that
          # hangs, are read from outside, because they can hang what reads
          # the journal too
          def fault_report(servers):
            for server in servers:
              try:
                stuck = "\n".join(fault_stuck(server)) or "(none)"
              except Exception as error:
                stuck = f"(unknown: {error})"
              print(f"stuck processes of {server.name}:\n{stuck}")
              try:
                _, journal = server.execute(
                  "journalctl --boot --no-pager --lines ${builtins.toString cfg.reportLines}${reportUnits}",
                  timeout=${builtins.toString cfg.reportTimeout},
                )
              except Exception as error:
                journal = f"(no journal: {error})"
              print(f"journal of {server.name}:\n{journal}")
              for command in fault_report_commands:
                try:
                  _, output = server.execute(command, timeout=${builtins.toString cfg.reportTimeout})
                except Exception as error:
                  output = f"(no output: {error})"
                print(f"{command} on {server.name}:\n{output}")
        ''
      ];
    };
}
