{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-proxy-haproxy = selfLib.test.contract.implementation {
    capability = "proxy";
    implementation = "haproxy";
    server = {
      toh.services.coredns.enable = true;
      toh.services.haproxy.enable = true;
    };
  };

  self.nixosTests = selfLib.test.proxyTests "haproxy";
}
