{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-email-maddy = selfLib.test.contract.implementation {
    capability = "email";
    implementation = "maddy";
    server = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.etcd.enable = true;
      toh.services.patroni.enable = true;
      toh.services.garage.enable = true;
      toh.services.lldap.enable = true;
      toh.services.maddy.enable = true;
    };
  };

  self.nixosTests.contracts-email-maddy = selfLib.test.makeNixosTest {
    toh.test.contracts.email = {
      enable = true;
      implementation.maddy = { };
    };
  };

  self.nixosTests.services-maddy = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = { config, ... }: {
        toh.programs.cli.enable = true;
        toh.services.coredns.enable = true;
        toh.services.envoy.enable = true;
        toh.services.etcd.enable = true;
        toh.services.patroni.enable = true;
        toh.services.garage.enable = true;
        toh.services.lldap.enable = true;
        toh.services.maddy.enable = true;

        toh.meta.email.apps.test = {
          user = config.toh.meta.user.user;
          group = config.toh.meta.user.group;
        };
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-email-online.target", timeout=300)''
      ''command_node.succeed("toh email maddy envelope list")''
    ];
  };
}
