{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-vault-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-vault-cluster";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.cockroachdb.enable = true;
          toh.services.vault.enable = true;
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active vault.service", timeout=180)''
          (node: ''
            command_node.wait_until_succeeds("""
              curl http://${node.toh.meta.network.ip}:8200/v1/sys/health | \
                grep -q 'initialized\":false'
            """, timeout=60)
          '')
          ''
            command_node.succeed("iptables -L -n | grep -q '8200'")
            command_node.succeed("iptables -L -n | grep -q '8201'")
          ''
        ];
      };
    };
}
