{ selfLib, ... }:

let
  test =
    network: mode:
    selfLib.test.makeNixosTest {
      toh.test.contracts.vpn = {
        enable = true;
        implementation.nebula = { };
        inherit network mode;
      };
    };
in
{
  self.lib.test.testModules.contracts-vpn-nebula = selfLib.test.contract.implementation {
    capability = "vpn";
    implementation = "nebula";
    server = {
      toh.services.nebula.enable = true;
    };
  };

  self.nixosTests.contracts-vpn-nebula-mesh = test "mesh" "proxy";
  self.nixosTests.contracts-vpn-nebula-relay-proxy = test "relay" "proxy";
  self.nixosTests.contracts-vpn-nebula-relay-punch = test "relay" "punch";
}
