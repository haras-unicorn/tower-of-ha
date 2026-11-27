{ lib, selfLib, ... }:

let
  test =
    network: mode:
    selfLib.test.makeNixosTest {
      toh.test.tier = 1;
      toh.test.contracts.vpn = {
        enable = true;
        implementation.easytier = { };
        inherit network mode;
      };
    };
in
{
  self.lib.test.testModules.contracts-vpn-easytier = selfLib.test.contract.implementation {
    capability = "vpn";
    implementation = "easytier";
    server = {
      toh.services.easytier.enable = true;
    };
    test =
      { config, ... }:
      let
        stunServers = config.toh.test.contracts.vpn.stunServers;
      in
      {
        toh.test.contracts.vpn.stun = true;
        toh.test.contracts.vpn.server = {
          toh.services.easytier.stunServers = lib.mkIf (stunServers != [ ]) stunServers;
        };
      };
  };

  self.nixosTests.contracts-vpn-easytier-mesh = test "mesh" "proxy";
  self.nixosTests.contracts-vpn-easytier-relay-proxy = test "relay" "proxy";
  self.nixosTests.contracts-vpn-easytier-relay-punch = test "relay" "punch";
}
