{ selfLib, ... }:

{
  self.nixosTests.services-nebula-mesh = selfLib.test.makeNixosTest {
    toh.test.mesh = {
      enable = true;
      name = "nebula";
      unit = "nebula@toh.service";
    };
  };

  self.nixosTests.services-nebula-relay = selfLib.test.makeNixosTest {
    toh.test.relay = {
      enable = true;
      name = "nebula";
      unit = "nebula@toh.service";
    };
  };
}
