{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-physical-backup-restore = pkgs.tohPackages.testers.runToHTest {
        name = "services-physical-backup-restore";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.programs.cli.enable = true;
          toh.programs.cli.enableBackup = true;
          toh.services.cockroachdb.enable = true;
          toh.services.seaweedfs.enable = true;

          services.cockroachdb.init.sql.scripts = [
            ''
              CREATE DATABASE IF NOT EXISTS testdb;
              CREATE TABLE IF NOT EXISTS testdb.backup_test (id INT PRIMARY KEY, message STRING);
              INSERT INTO testdb.backup_test VALUES (1, 'test data for backup');
            ''
          ];
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)''
          ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-initialized.target", timeout=180)''
        ];
        toh.test.commands.suffix = ''
          node1.succeed("""
            toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1' | \
              grep -q 'test data for backup'
          """)

          node1.succeed("""
            echo 'SeaweedFS backup test content' > /tmp/sw-testfile.txt
          """)
          node1.succeed("""
            curl -F file=@/tmp/sw-testfile.txt http://192.168.1.10:8888/testbackup/
          """)
          node1.wait_until_succeeds("""
            curl -f http://192.168.1.10:8888/testbackup/sw-testfile.txt | \
              grep -q 'SeaweedFS backup test content'
          """, timeout=60)

          backup_output = node1.succeed("cd /tmp && toh backup physical")
          quoted_password = backup_output.split(" ")[-1].strip()
          node1.wait_for_unit("toh-database-initialized.target", timeout=180)
          node1.wait_for_unit("toh-filesystem-initialized.target", timeout=180)

          node1.succeed("toh cockroachdb root sql --execute 'DROP DATABASE testdb CASCADE'")
          node1.fail("toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1'")
          node1.succeed("""
            curl -X DELETE http://192.168.1.10:8888/testbackup/sw-testfile.txt
          """)
          node1.fail("""
            curl -f http://192.168.1.10:8888/testbackup/sw-testfile.txt
          """)

          node1.succeed(f"cd /tmp && echo {quoted_password} | toh restore physical")
          node1.wait_for_unit("toh-database-initialized.target", timeout=180)
          node1.wait_for_unit("toh-filesystem-initialized.target", timeout=180)

          node1.succeed("""
            toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1' | \
              grep -q 'test data for backup'
          """)
          node1.succeed("""
            curl -sf http://192.168.1.10:8888/testbackup/sw-testfile.txt | \
              grep -q 'SeaweedFS backup test content'
          """)
        '';
      };

      checks.test-services-logical-backup-restore = pkgs.tohPackages.testers.runToHTest {
        name = "services-logical-backup-restore";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.programs.cli.enable = true;
          toh.programs.cli.enableBackup = true;
          toh.services.cockroachdb.enable = true;
          toh.services.seaweedfs.enable = true;

          services.cockroachdb.init.sql.scripts = [
            ''
              CREATE DATABASE IF NOT EXISTS testdb;
              CREATE TABLE IF NOT EXISTS testdb.backup_test (id INT PRIMARY KEY, message STRING);
              INSERT INTO testdb.backup_test VALUES (1, 'test data for backup');
            ''
          ];
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-database-initialized.target", timeout=180)''
          ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-initialized.target", timeout=180)''
        ];
        toh.test.commands.suffix = ''
          node1.succeed("""
            toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1' | \
              grep -q 'test data for backup'
          """)

          node1.succeed("""
            echo 'SeaweedFS backup test content' > /tmp/sw-testfile.txt
          """)
          node1.succeed("""
            curl -F file=@/tmp/sw-testfile.txt http://192.168.1.10:8888/testbackup/
          """)
          node1.wait_until_succeeds("""
            curl -f http://192.168.1.10:8888/testbackup/sw-testfile.txt | \
              grep -q 'SeaweedFS backup test content'
          """, timeout=60)

          backup_output = node1.succeed("cd /tmp && toh backup logical")
          quoted_password = backup_output.split(" ")[-1].strip()
          node1.wait_for_unit("toh-database-initialized.target", timeout=180)
          node1.wait_for_unit("toh-filesystem-initialized.target", timeout=180)

          node1.succeed("toh cockroachdb root sql --execute 'DROP DATABASE testdb CASCADE'")
          node1.fail("toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1'")
          node1.succeed("""
            curl -X DELETE http://192.168.1.10:8888/testbackup/sw-testfile.txt
          """)
          node1.fail("""
            curl -f http://192.168.1.10:8888/testbackup/sw-testfile.txt
          """)

          node1.succeed(f"cd /tmp && echo {quoted_password} | toh restore logical")
          node1.wait_for_unit("toh-database-initialized.target", timeout=180)
          node1.wait_for_unit("toh-filesystem-initialized.target", timeout=180)

          node1.succeed("""
            toh cockroachdb root sql --execute 'SELECT message FROM testdb.backup_test WHERE id=1' | \
              grep -q 'test data for backup'
          """)
          node1.succeed("""
            curl -sf http://192.168.1.10:8888/testbackup/sw-testfile.txt | \
              grep -q 'SeaweedFS backup test content'
          """)
        '';
      };
    };
}
