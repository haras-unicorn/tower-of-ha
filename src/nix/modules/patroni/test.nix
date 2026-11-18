{ selfLib, ... }:

{
  self.nixosTests.services-patroni = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.haproxy.enable = true;
        toh.services.patroni.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      (
        node:
        let
          url = selfLib.services.endpoint.toUrl node.toh.meta.proxies.patroni.endpoint {
            path = "health";
          };
        in
        ''command_node.wait_until_succeeds("curl -f ${url}", timeout=300)''
      )
      ''command_node.succeed("patronictl list")''
    ];
  };

  self.nixosTests.services-patroni-init = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.haproxy.enable = true;
        toh.services.patroni.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      (
        node:
        let
          url = selfLib.services.endpoint.toUrl node.toh.meta.proxies.patroni.endpoint {
            path = "health";
          };
        in
        ''command_node.wait_until_succeeds("curl -f ${url}", timeout=300)''
      )
      ''command_node.succeed("patronictl list")''
    ];
  };

  self.nixosTests.services-patroni-cli = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.programs.cli.enable = true;
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.haproxy.enable = true;
        toh.services.patroni.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      ''command_node.succeed("toh psql postgres -d __toh_initialization -c 'select * from initializations;'")''
    ];
  };

  self.nixosTests.services-patroni-app = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.programs.cli.enable = true;
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.haproxy.enable = true;
        toh.services.patroni.enable = true;
        toh.meta.database.apps.test = {
          user = "test";
          group = "test";
          init.sql.script = ''
            create table test (test text);
          '';
        };
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      ''command_node.succeed("toh psql test -d test -c \"insert into test values ('test');\"")''
      ''command_node.succeed("toh psql test -d test -c \"select test from test where test = 'test';\"")''
    ];
  };
}
