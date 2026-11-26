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

  # NOTE: the names of services point at the relays, and a relay that goes
  # away leaves the answers of the others, so a client that only tries the
  # first address still reaches a relay that is up; a machine that is split
  # off refuses other machines, so they ask a nameserver that is not
  self.nixosTests.services-coredns-relays = selfLib.test.makeNixosTest {
    toh.test.clusters.node.amount = 3;
    toh.test.clusters.node.module = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
    };

    toh.test.faults.amount = 2;

    toh.test.commands.enable = true;
    toh.test.commands.suffix =
      { nodes, ... }:
      let
        name = "any.${nodes.node1.toh.meta.domains.service}";
        lost = nodes.node1.toh.meta.network.ip;
        asked = nodes.node2.toh.meta.network.ip;
        answers = server: "dig +short @${server} ${name} A";
      in
      ''
        for node in [node1, node2, node3]:
          node.wait_for_unit("coredns.service")
          node.wait_for_unit("envoy.service")

        node3.wait_until_succeeds("${answers asked} | grep -x ${lost}", timeout=60)
        node2.succeed("${answers "127.0.0.1"} | grep -x 127.0.0.1")
        node3.fail("${answers asked} | grep -x 127.0.0.1")

        fault_kill(node1)
        node3.wait_until_fails("${answers asked} | grep -x ${lost}", timeout=30)
        node3.succeed("${answers asked} | grep -x ${nodes.node3.toh.meta.network.ip}")

        fault_revive(node1)
        node1.wait_for_unit("envoy.service")
        node3.wait_until_succeeds("${answers asked} | grep -x ${lost}", timeout=60)

        fault_split(node1, [node2, node3])
        node1.wait_until_succeeds("dig @${lost} ${name} A | grep -qE 'status: (REFUSED|SERVFAIL)'", timeout=30)
        node1.succeed("${answers "127.0.0.1"} | grep -x 127.0.0.1")
        node3.wait_until_fails("${answers asked} | grep -x ${lost}", timeout=30)

        fault_join(node1, [node2, node3])
        node1.wait_until_succeeds("${answers lost} | grep -x ${lost}", timeout=60)
        node3.wait_until_succeeds("${answers asked} | grep -x ${lost}", timeout=60)
      '';
  };
}
