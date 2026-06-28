{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-forgejo = pkgs.tohPackages.testers.runToHTest {
        name = "services-forgejo";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.patroni.enable = true;
            toh.services.cephfs.enable = true;
            toh.services.garage.enable = true;
            toh.services.valkey.enable = true;
            toh.services.lldap.enable = true;
            toh.services.maddy.enable = true;
            toh.services.authelia.enable = true;
            toh.services.forgejo.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-git-online.target", timeout=300)''
        ];
      };

      checks.test-services-forgejo-runner = pkgs.tohPackages.testers.runToHTest {
        name = "services-forgejo-runner";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.patroni.enable = true;
            toh.services.cephfs.enable = true;
            toh.services.garage.enable = true;
            toh.services.valkey.enable = true;
            toh.services.lldap.enable = true;
            toh.services.maddy.enable = true;
            toh.services.authelia.enable = true;
            toh.services.forgejo.enable = true;
            toh.services.forgejo.runner.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-git-online.target", timeout=300)''
        ];
      };
    };
}
