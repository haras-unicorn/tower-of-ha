{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-etcd = pkgs.tohPackages.testers.runToHTest {
        name = "services-etcd";

        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.services.etcd.enable = true;
        };

        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-config-initialized.target", timeout=180)''
          ''command_node.succeed("systemctl is-active etcd.service")''
          (
            node:
            let
              clientUrl = builtins.head node.services.etcd.listenClientUrls;
              cacrt = node.services.etcd.trustedCaFile;
              cert = node.services.etcd.certFile;
              key = node.services.etcd.keyFile;
            in
            ''
              command_node.succeed("""
                curl \
                  --cacert ${cacrt} \
                  --cert ${cert} \
                  --key ${key} \
                  -f \
                  ${clientUrl}/health
              """)
              command_node.succeed("""
                etcdctl \
                  --endpoints=${clientUrl} \
                  --cacert=${cacrt} \
                  --cert=${cert} \
                  --key=${key} \
                  member list \
                  | grep -c 'started' \
                  | grep 3
              """)
            ''
          )
        ];
      };
    };
}
