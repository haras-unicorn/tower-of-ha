{ self, ... }:

{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-vault-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-vault-disabled";
        toh.test.disabledService.module = {
          imports = [
            self.nixosModules.services-vault
          ];
        };
        toh.test.disabledService.enable = true;
        toh.test.disabledService.name = "vault.service";

      };

      checks.test-services-vault-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-vault-cluster";
        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          imports = [
            self.nixosModules.services-vault
          ];

          toh.test.cockroachdb.enable = true;
          toh.vault.enable = true;
        };
        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active vault.service", timeout=180)''
          (node: ''
            command_node.wait_until_succeeds("""
              curl http://${node.toh.host.ip}:8200/v1/sys/health | \
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
