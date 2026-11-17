{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-openbao = pkgs.tohPackages.testers.runToHTest {
        name = "services-openbao-cluster";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.coredns.enable = true;
          toh.services.haproxy.enable = true;
          toh.services.etcd.enable = true;
          toh.services.openbao.enable = true;
          toh.services.patroni.enable = true;
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active openbao.service", timeout=180)''
          ''command_node.wait_until_succeeds("systemctl is-active openbao-initialization.service", timeout=180)''
          ''
            command_node.wait_until_succeeds("""
              [ "$(systemctl show -p ActiveState --value openbao-fetch-token.service)" = inactive ]
            """, timeout=180)
            command_node.succeed("! systemctl is-failed openbao-fetch-token.service")
          ''
        ];
      };
    };
}
