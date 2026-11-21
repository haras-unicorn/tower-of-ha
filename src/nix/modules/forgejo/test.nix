{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-git-forgejo = selfLib.test.contract.implementation {
    capability = "git";
    implementation = "forgejo";
    server = {
      toh.services.etcd.enable = true;
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.patroni.enable = true;
      toh.services.cephfs.enable = true;
      toh.services.garage.enable = true;
      toh.services.valkey.enable = true;
      toh.services.lldap.enable = true;
      toh.services.maddy.enable = true;
      toh.services.authelia.enable = true;
      toh.services.forgejo.enable = true;
    };
  };

  self.nixosTests.contracts-git-forgejo = selfLib.test.makeNixosTest {
    toh.test.contracts.git = {
      enable = true;
      implementation.forgejo = { };
    };
  };

  self.nixosTests.services-forgejo = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.envoy.enable = true;
        toh.services.patroni.enable = true;
        toh.services.cephfs.enable = true;
        toh.services.garage.enable = true;
        toh.services.valkey.enable = true;
        toh.services.lldap.enable = true;
        toh.services.maddy.enable = true;
        toh.services.authelia.enable = true;
        toh.services.forgejo.enable = true;
        toh.services.forgejo.runner.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-git-online.target", timeout=300)''
    ];
  };
}
