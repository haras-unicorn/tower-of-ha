{
  self.lib.test.testModules.tiers =
    { lib, config, ... }:
    let
      cfg = config.toh.test;
    in
    {
      options.toh.test = {
        tier = lib.mkOption {
          type = lib.types.ints.between 1 3;
          description = ''
            How often the test runs, set by hand on every test: tier 1 checks
            the happy path and runs on every change, tier 2 makes faults, and
            tier 3 runs on VMs. `dev test --tier <n>` runs the tests of tier n
            and below.
          '';
        };

        budgets = lib.mkOption {
          type = lib.types.attrsOf lib.types.ints.positive;
          default = {
            "1" = 300;
            "2" = 600;
            "3" = 600;
          };
          description = ''
            Seconds a test of each tier may run for, which becomes its global
            timeout. A test that needs more sets its own global timeout and
            says why; one that runs much faster may set less.
          '';
        };
      };

      config = {
        globalTimeout = lib.mkDefault cfg.budgets.${builtins.toString cfg.tier};

        # NOTE: a passthru attribute can be read without evaluating the
        # machines of the test, so `dev test` picks the tests quickly
        passthru.tier = cfg.tier;
      };
    };
}
