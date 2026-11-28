{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-database-patroni = selfLib.test.contract.implementation {
    capability = "database";
    implementation = "patroni";
    server = {
      toh.services.etcd.enable = true;
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.patroni.enable = true;
    };
    test.toh.test.contracts.database.redundant = selfLib.test.redundant.patroni;
  };

  self.lib.test.faultTests.contracts-database-patroni = {
    toh.test.contracts.database = {
      enable = true;
      implementation.patroni = { };
    };
  };

  self.nixosTests.services-patroni = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.envoy.enable = true;
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

  # NOTE: every step of the init adds its kind to the runs table, so the
  # table shows which steps ran, in what order and how often
  self.nixosTests.services-patroni-init = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      first = builtins.head machineList;
      second = builtins.elemAt machineList 1;
      runs = ''toh psql postgres -d postgres -t -A -c \"select string_agg(kind, ',' order by id) from init_runs\"'';
    in
    {
      toh.test.tier = 1;
      toh.test.clusters.node = {
        amount = 3;
        module =
          { config, pkgs, ... }:
          let
            env = config.toh.services.patroni.users.${selfLib.patroni.superusers.superuser}.env;
            unitScript = pkgs.writeText "init-check.nu" ''
              open --raw "${env}" | from toml | load-env
              psql -d postgres --set=ON_ERROR_STOP=on -c "insert into init_runs (kind) values ('systemd')"
            '';
          in
          {
            toh.programs.cli.enable = true;
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.envoy.enable = true;
            toh.services.patroni.enable = true;

            toh.services.patroni.init = {
              sql.scripts = [
                {
                  init-check = ''
                    \c postgres
                    create table init_runs (id serial primary key, kind text);
                    insert into init_runs (kind) values ('sql');
                  '';
                }
              ];
              systemd.units = [ { init-check = "init-check.service"; } ];
              nushell.scripts = [
                {
                  init-check = ''
                    psql -d postgres --set=ON_ERROR_STOP=on -c "insert into init_runs (kind) values ('nushell')"
                  '';
                }
              ];
            };

            systemd.services.init-check = {
              path = [ config.services.patroni.postgresqlPackage ];
              script = "${pkgs.nushell}/bin/nu ${unitScript}";
              serviceConfig.Type = "oneshot";
            };
          };
      };

      toh.test.commands.perNodeInCluster.node = [
        ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      ];

      toh.test.commands.suffix = ''
        output = ${first.toh.meta.machine.name}.succeed("${runs}")
        assert output.strip() == "sql,systemd,nushell", output
        output = ${first.toh.meta.machine.name}.succeed(
          "toh psql postgres -d __toh_initialization -t -A -c 'select status from initializations'"
        )
        assert output.strip() == "completed", output

        ${second.toh.meta.machine.name}.succeed("systemctl restart patroni-initialization.service")
        output = ${second.toh.meta.machine.name}.succeed("${runs}")
        assert output.strip() == "sql,systemd,nushell", output
      '';
    }
  );

  self.nixosTests.services-patroni-cli = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.programs.cli.enable = true;
        toh.services.etcd.enable = true;
        toh.services.coredns.enable = true;
        toh.services.envoy.enable = true;
        toh.services.patroni.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-database-online.target", timeout=300)''
      ''command_node.succeed("toh psql postgres -d __toh_initialization -c 'select * from initializations;'")''
    ];
  };
}
