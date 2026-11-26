{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-secrets-openbao = selfLib.test.contract.implementation {
    capability = "secrets";
    implementation = "openbao";
    server = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.etcd.enable = true;
      toh.services.openbao.enable = true;
      toh.services.patroni.enable = true;
    };
    test = {
      toh.test.contracts.secrets = {
        # NOTE: OpenBao has no target of its own
        online = "openbao.service";
        redundant = selfLib.test.redundant.patroni;
      };
      # NOTE: etcd logs every heartbeat it cannot send while a server is
      # cut off, which would push OpenBao and its database out of the report
      toh.test.faults.reportUnits = [
        "openbao*"
        "patroni.service"
        "envoy.service"
      ];
      # NOTE: which connections each server still holds, with their timers,
      # which shows one that waits on a server that was cut off
      toh.test.faults.reportCommands = [ "ss -tnpo" ];
    };
  };

  self.lib.test.faultTests.contracts-secrets-openbao = {
    toh.test.contracts.secrets = {
      enable = true;
      implementation.openbao = { };
    };
  };

  self.nixosTests.services-openbao = selfLib.test.makeNixosTest {
    toh.test.clusters.node.amount = 3;
    toh.test.clusters.node.module = {
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.etcd.enable = true;
      toh.services.openbao.enable = true;
      toh.services.patroni.enable = true;
    };

    toh.test.commands.enable = true;
    toh.test.commands.perNode = [
      ''command_node.wait_until_succeeds("systemctl is-active openbao.service", timeout=180)''
      ''command_node.wait_until_succeeds("systemctl is-active openbao-initialization.service", timeout=180)''
      ''
        command_node.wait_until_succeeds("""
          [ "$(systemctl show -p ActiveState --value openbao-fetch-token.service)" = inactive ]
        """, timeout=180)
        command_node.succeed("! systemctl is-failed openbao-fetch-token.service")
      ''
    ];
  };
}
