{ selfLib, ... }:

let
  # NOTE: latitude, longitude, altitude and accuracy, one per line, in the
  # format of /etc/geolocation
  latitude = "45.8150";
  longitude = "15.9819";
  altitude = "120";
  accuracy = "1000";
  location = ''
    ${latitude}
    ${longitude}
    ${altitude}
    ${accuracy}
  '';
in
{
  self.nixosTests.services-geoclue = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.cryl.cluster = [
      {
        geoclue = {
          generations = [
            {
              generator = "text";
              arguments = {
                name = "origin-homelab-geoclue-static-geolocation";
                text = location;
              };
            }
          ];
        };
      }
    ];

    containers.machine = {
      toh.services.geoclue.enable = true;
    };

    toh.test.commands.suffix = ''
      machine.wait_for_unit("avahi-daemon.service", timeout=120)
      machine.wait_for_unit("geoclue.service", timeout=120)
      machine.succeed("test \"$(stat -c %U /etc/geolocation)\" = geoclue")
      output = machine.succeed("cat /etc/geolocation")
      assert output.split() == "${latitude} ${longitude} ${altitude} ${accuracy}".split(), output
    '';
  };
}
