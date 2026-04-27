{ self, ... }:

{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-vaultwarden-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-vaultwarden-disabled";
        toh.test.disabledService.module = {
          imports = [
            self.nixosModules.services-vaultwarden
          ];
        };
        toh.test.disabledService.enable = true;
        toh.test.disabledService.name = "vaultwarden.service";

      };

      checks.test-services-vaultwarden-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-vaultwarden-cluster";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          imports = [
            self.nixosModules.services-vaultwarden
          ];

          toh.test.cockroachdb.enable = true;
          toh.vaultwarden.enable = true;
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active vaultwarden.service", timeout=180)''
          ''command_node.wait_until_succeeds("curl -f http://192.168.1.10:8222/alive", timeout=60)''
          ''command_node.succeed("iptables -L -n | grep -q '8222'")''
        ];
      };
    };
}
