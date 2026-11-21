{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-proxy-envoy = selfLib.test.contract.implementation {
    capability = "proxy";
    implementation = "envoy";
    server = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
    };
  };

  self.nixosTests = selfLib.test.proxyTests "envoy";
}
