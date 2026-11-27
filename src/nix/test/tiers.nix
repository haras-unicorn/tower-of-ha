{
  self.lib.test.testModules.tiers =
    { lib, config, ... }:
    {
      options.toh.test.tier = lib.mkOption {
        type = lib.types.ints.between 1 3;
        description = ''
          How often the test runs, set by hand on every test: tier 1 checks
          the happy path and runs on every change, tier 2 makes faults, and
          tier 3 runs on VMs. `dev test --tier <n>` runs the tests of tier n
          and below.
        '';
      };

      # NOTE: a passthru attribute can be read without evaluating the
      # machines of the test, so `dev test` picks the tests quickly
      config.passthru.tier = config.toh.test.tier;
    };
}
