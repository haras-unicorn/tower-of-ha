{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-nebula-mesh = pkgs.tohPackages.testers.runToHTest {
        toh.test.mesh = {
          enable = true;
          name = "nebula";
          unit = "nebula@toh.service";
        };
      };

      checks.test-services-nebula-relay = pkgs.tohPackages.testers.runToHTest {
        toh.test.relay = {
          enable = true;
          name = "nebula";
          unit = "nebula@toh.service";
        };
      };
    };
}
