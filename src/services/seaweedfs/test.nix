{ self, ... }:

{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-seaweedfs-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-seaweedfs-disabled";
        toh.test.disabledService.module = { };
        toh.test.disabledService.enable = true;
        toh.test.disabledService.name = "seaweedfs.service";

      };

      checks.test-services-seaweedfs-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-seaweedfs-cluster";
        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.test.cockroachdb.enable = true;
          toh.test.seaweedfs.enable = true;
        };
        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_for_unit("toh-filesystem-initialized", timeout=60)''
          (node: ''
            command_node.wait_until_succeeds("""
              curl -f http://${node.toh.host.ip}:9333/cluster/status
            """, timeout=60)
          '')
          (node: ''
            command_node.wait_until_succeeds("""
              curl -f http://${node.toh.host.ip}:8888/
            """, timeout=60)
          '')
          (node: ''
            command_node.succeed("""
              curl -f http://${node.toh.host.ip}:8081/status | \
                grep -q 'Version'
            """)
          '')
          (
            { node, nodea, ... }:
            builtins.map (
              other:
              # NOTE: it lists only peers but not itself
              if other.toh.host.ip == node.toh.host.ip then
                ""
              else
                ''
                  command_node.succeed("""
                    curl -f http://${node.toh.host.ip}:9333/cluster/status | \
                      grep -q '${other.toh.host.ip}'
                  """)
                ''
            ) nodea
          )
        ];
        toh.test.commands.suffix = ''
          node1.succeed("""
            echo 'Hello from SeaweedFS cluster test' \
              > /tmp/testfile.txt
          """)

          node1.succeed("""
            curl -F file=@/tmp/testfile.txt http://192.168.1.10:8888/testfolder/
          """)

          node2.wait_until_succeeds("""
            curl -f http://192.168.1.11:8888/testfolder/testfile.txt | \
              grep 'Hello from SeaweedFS cluster test'
          """, timeout=60)
          node3.wait_until_succeeds("""
            curl -f http://192.168.1.12:8888/testfolder/testfile.txt | \
              grep 'Hello from SeaweedFS cluster test'
          """, timeout=60)
          node1.succeed("""
            curl -f http://192.168.1.10:8888/testfolder/ | \
              grep 'testfile.txt'
          """)
        '';
      };
    };
}
