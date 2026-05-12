{
  perSystem =
    { pkgs, tohLib, ... }:
    {
      checks.test-services-geoclue = pkgs.tohPackages.testers.runToHTest {
        name = "services-geoclue";

        toh.test.cryl.cluster = [
          {
            geoclue = {
              generations = [
                {
                  generator = "text";
                  arguments = {
                    name = "origin-homelab-geoclue-static-geolocation";
                    text = "1";
                  };
                }
              ];
            };
          }
        ];

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
