# NOTE: the faults of step 8 as python helpers, so every test breaks its
# machines the same way; what a test checks after a fault is in
# docs/design.md, under the decisions of 2026-11-25

{
  self.lib.test.testModules.faults =
    { lib, config, ... }:
    let
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
        ''
      ];
    };
}
