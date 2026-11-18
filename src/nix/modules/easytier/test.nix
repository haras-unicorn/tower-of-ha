{ selfLib, ... }:

{
  self.nixosTests.services-easytier-mesh = selfLib.test.makeNixosTest {
    toh.test.mesh = {
      enable = true;
      name = "easytier";
      unit = "easytier-toh.service";
    };
  };

  self.nixosTests.services-easytier-relay-proxy = selfLib.test.makeNixosTest {
    toh.test.relay = {
      enable = true;
      name = "easytier";
      unit = "easytier-toh.service";
      mode = "proxy";
    };
  };

  self.nixosTests.services-easytier-relay-punch = selfLib.test.makeNixosTest {
    toh.test.relay = {
      enable = true;
      name = "easytier";
      unit = "easytier-toh.service";
      mode = "punch";
      stun = true;
    };
  };
}
