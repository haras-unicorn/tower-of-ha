{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-cephfs = pkgs.tohPackages.testers.runToHTest {
        name = "services-cephfs";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.services.cephfs.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-initialized.target", timeout=300)''
          ''
            import json
            status = json.loads(command_node.succeed("ceph -s --format json"))
            assert (
              status["health"]["status"] == "HEALTH_OK"
              or (
                status["health"]["status"] == "HEALTH_WARN"
                and list(status["health"]["checks"].keys()) == ["MON_CLOCK_SKEW"]
              )
            ), f"CephFS is suffering from something other than regular clock skew in tests: '{status}'"
          ''
        ];
      };

      checks.test-services-cephfs-mount = pkgs.tohPackages.testers.runToHTest {
        name = "services-cephfs-mount";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.services.cephfs.enable = true;
            toh.meta.filesystem.mounts."/mnt" = { };
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-initialized.target", timeout=300)''
          ''
            import json
            status = json.loads(command_node.succeed("ceph -s --format json"))
            assert (
              status["health"]["status"] == "HEALTH_OK"
              or (
                status["health"]["status"] == "HEALTH_WARN"
                and list(status["health"]["checks"].keys()) == ["MON_CLOCK_SKEW"]
              )
            ), f"CephFS is suffering from something other than regular clock skew in tests: '{status}'"
          ''
          (
            node:
            let
              name = node.toh.meta.machine.name;
            in
            ''
              command_node.succeed("echo 'Hello from ${name}!' > /mnt/hello-world-${name}")
            ''
          )
          (
            { node, nodea, ... }:
            let
              others = builtins.filter (other: other.toh.meta.machine.name != node.toh.meta.machine.name) nodea;
            in
            builtins.concatStringsSep "\n" (
              builtins.map (
                other:
                let
                  name = other.toh.meta.machine.name;
                in
                ''command_node.succeed("cat /mnt/hello-world-${name} | grep -q 'Hello from ${name}!'")''
              ) others
            )
          )
        ];
      };
    };
}
