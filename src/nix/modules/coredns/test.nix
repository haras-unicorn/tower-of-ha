{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-dns-coredns = selfLib.test.contract.implementation {
    capability = "dns";
    implementation = "coredns";
    server = {
      toh.services.coredns.enable = true;
    };
  };

  self.nixosTests.contracts-dns-coredns = selfLib.test.makeNixosTest {
    toh.test.contracts.dns = {
      enable = true;
      implementation.coredns = { };
    };
  };

  self.nixosTests.services-coredns = selfLib.test.makeNixosTest {
    toh.test.dns.enable = true;
    toh.test.dns.zones = {
      "test.toh" = {
        "localhost.test.toh" = "127.0.0.1";
      };
    };

    containers.machine = {
      toh.services.coredns.enable = true;
    };

    toh.test.commands.suffix =
      { nodes, ... }:
      ''
        machine.wait_for_unit("coredns.service")
        machine.succeed("getent hosts localhost.test.toh | grep -q '127.0.0.1'")
        machine.succeed("dig @${nodes.dns.toh.meta.network.ip} localhost.test.toh | grep -q '127.0.0.1'")
      '';
  };
}
