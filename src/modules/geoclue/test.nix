{
  perSystem =
    { pkgs, tohLib, ... }:
    {
      checks.test-services-geoclue-enabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-geoclue-enabled";

        toh.test.cryl.cluster.geoclue = {
          generations = [
            {
              generator = "text";
              arguments = {
                name = "geoclue-static-geolocation";
                text = "1";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "geoclue-static-geolocation";
                to = "${tohLib.secrets.directories.cluster}/geoclue-static-geolocation";
              };
            }
          ];
        };

        nodes.machine = {
          toh.services.geoclue.enable = true;
        };

        toh.test.commands.suffix = ''
          machine.wait_for_unit("avahi-daemon.service")
          machine.wait_for_unit("geoclue.service")
        '';
      };
    };
}
