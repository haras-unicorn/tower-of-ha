{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-forgejo = pkgs.tohPackages.testers.runToHTest {
        name = "services-forgejo";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.programs.cli.enable = true;
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.patroni.enable = true;
            toh.services.garage.enable = true;
            toh.services.valkey.enable = true;
            toh.services.cephfs.enable = true;
            toh.services.forgejo.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active forgejo.service", timeout=600)''
        ];

        toh.test.commands.perNode = [
          # NOTE: works only for a single node for now
          # (only the first node lands on a node1 command)
          (
            node:
            let
              ip = node.toh.meta.network.ip;
            in
            ''command_node.wait_until_succeeds("curl -f http://${ip}:3000/api/healthz", timeout=300)''
          )
        ];
      };
    };
}
