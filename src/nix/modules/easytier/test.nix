{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-easytier-mesh = pkgs.tohPackages.testers.runToHTest {
        toh.test.mesh = {
          enable = true;
          name = "easytier";
          unit = "easytier-toh.service";
        };
      };

      checks.test-services-easytier-relay = pkgs.tohPackages.testers.runToHTest {
        toh.test.relay = {
          enable = true;
          name = "easytier";
          unit = "easytier-toh.service";
        };
      };
    };
}
