{ selfLib, ... }:

{
  self.nixosTests.services-easytier-mesh = selfLib.test.makeNixosTest {
    toh.test.mesh = {
      enable = true;
      name = "easytier";
      unit = "easytier-toh.service";
    };
  };

  self.nixosTests.services-easytier-relay = selfLib.test.makeNixosTest {
    toh.test.relay = {
      enable = true;
      name = "easytier";
      unit = "easytier-toh.service";
    };
  };
}
