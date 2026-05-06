{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-cockroachdb-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-cockroachdb-cluster";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.cockroachdb.enable = true;

          services.cockroachdb.init.sql.scripts = [
            ''
              CREATE DATABASE IF NOT EXISTS testdb;
            ''
          ];
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)''
          ''command_node.succeed("which cockroach")''
          (node: ''
            command_node.wait_until_succeeds("""
              curl -kf --max-time 5 https://${node.toh.meta.network.ip}:8080/health
            """, timeout=30)
          '')
          ''
            command_node.succeed("iptables -L -n | grep -q '26257'")
            command_node.succeed("iptables -L -n | grep -q '26258'")
            command_node.succeed("iptables -L -n | grep -q '8080'")
          ''
        ];
      };

      # NOTE: the non-root variant just uses sudo to read the env file so its ok to not test it
      checks.test-services-cockroachdb-cli-root-root = pkgs.tohPackages.testers.runToHTest {
        name = "services-cockroachdb-cli-root-root";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.cockroachdb.enable = true;
          toh.programs.cli.enable = true;

          services.cockroachdb.init.sql.scripts = [
            ''
              CREATE DATABASE IF NOT EXISTS testdb;
            ''
          ];
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)''
        ];
        toh.test.commands.suffix = ''
          node1.succeed("""
            toh cockroachdb root sql \
              --execute 'CREATE TABLE IF NOT EXISTS testdb.replication_test (id INT PRIMARY KEY, message STRING)'
          """)
          node1.succeed("""
            toh cockroachdb root sql \
              --execute "INSERT INTO testdb.replication_test VALUES (1, 'hello from cluster')"
          """)

          node2.succeed("""
            toh cockroachdb root sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)
          node3.succeed("""
            toh cockroachdb root sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)

          node1.wait_until_succeeds("""
            toh cockroachdb root sql \
              --execute 'SELECT COUNT(*) FROM crdb_internal.gossip_nodes' 2>/dev/null \
              | grep -q '3'
          """)
        '';
      };

      checks.test-services-cockroachdb-cli-root-non-machine = pkgs.tohPackages.testers.runToHTest {
        name = "services-cockroachdb-root-non-machine";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.cockroachdb.enable = true;
          toh.programs.cli.enable = true;

          services.cockroachdb.init.sql.scripts = [
            ''
              CREATE DATABASE IF NOT EXISTS testdb;
            ''
          ];
        };

        toh.test.commands.enable = true;
        toh.test.commands.suffix = ''
          node1.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)
          node2.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)
          node3.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)

          machine.succeed("""
            toh cockroachdb root sql \
              --execute 'CREATE TABLE IF NOT EXISTS testdb.replication_test (id INT PRIMARY KEY, message STRING)'
          """)
          machine.succeed("""
            toh cockroachdb root sql \
              --execute "INSERT INTO testdb.replication_test VALUES (1, 'hello from cluster')"
          """)
          machine.succeed("""
            toh cockroachdb root sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)
        '';
      };

      # NOTE: the user/non-root variant just reads the file normally so its pretty much the same
      checks.test-services-cockroachdb-cli-user-root = pkgs.tohPackages.testers.runToHTest {
        name = "services-cockroachdb-cli-user-root";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module =
          { config, ... }:
          let
            user = config.toh.meta.user.user;
          in
          {
            toh.services.cockroachdb.enable = true;
            toh.programs.cli.enable = true;

            services.cockroachdb.init.sql.scripts = [
              ''
                CREATE DATABASE IF NOT EXISTS testdb;

                use testdb;

                alter default privileges for all roles in schema public grant all on tables to ${user};
                alter default privileges for all roles in schema public grant all on sequences to ${user};
                alter default privileges for all roles in schema public grant all on functions to ${user};

                grant all on all tables in schema public to ${user};
                grant all on all sequences in schema public to ${user};
                grant all on all functions in schema public to ${user};

                reset database;
              ''
            ];
          };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)''
        ];
        toh.test.commands.suffix = ''
          node1.succeed("""
            toh cockroachdb user sql \
              --execute 'CREATE TABLE IF NOT EXISTS testdb.replication_test (id INT PRIMARY KEY, message STRING)'
          """)
          node1.succeed("""
            toh cockroachdb user sql \
              --execute "INSERT INTO testdb.replication_test VALUES (1, 'hello from cluster')"
          """)

          node2.succeed("""
            toh cockroachdb user sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)
          node3.succeed("""
            toh cockroachdb user sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)
        '';
      };

      checks.test-services-cockroachdb-cli-user-non-machine = pkgs.tohPackages.testers.runToHTest {
        name = "services-cockroachdb-user-non-machine";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module =
          { config, ... }:
          let
            user = config.toh.meta.user.user;
          in
          {
            toh.services.cockroachdb.enable = true;

            services.cockroachdb.init.sql.scripts = [
              ''
                CREATE DATABASE IF NOT EXISTS testdb;

                use testdb;

                alter default privileges for all roles in schema public grant all on tables to ${user};
                alter default privileges for all roles in schema public grant all on sequences to ${user};
                alter default privileges for all roles in schema public grant all on functions to ${user};

                grant all on all tables in schema public to ${user};
                grant all on all sequences in schema public to ${user};
                grant all on all functions in schema public to ${user};

                reset database;
              ''
            ];
          };

        nodes.machine = {
          toh.programs.cli.enable = true;
        };

        toh.test.commands.enable = true;
        toh.test.commands.suffix = ''
          node1.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)
          node2.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)
          node3.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)

          machine.succeed("""
            toh cockroachdb user sql \
              --execute 'CREATE TABLE IF NOT EXISTS testdb.replication_test (id INT PRIMARY KEY, message STRING)'
          """)
          machine.succeed("""
            toh cockroachdb user sql \
              --execute "INSERT INTO testdb.replication_test VALUES (1, 'hello from cluster')"
          """)
          machine.succeed("""
            toh cockroachdb user sql \
              --execute 'SELECT message FROM testdb.replication_test WHERE id=1' | \
              grep -q 'hello from cluster'
          """)
        '';
      };
    };

}
