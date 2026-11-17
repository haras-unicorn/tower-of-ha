{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.test-services-valkey = pkgs.tohPackages.testers.runToHTest {
        name = "services-valkey";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.programs.cli.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.coredns.enable = true;
            toh.services.valkey.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-kv-online.target", timeout=300)''
          ''command_node.wait_until_succeeds("toh valkey valkey ping | grep -q 'PONG'", timeout=30)''
        ];
      };
    };
}
