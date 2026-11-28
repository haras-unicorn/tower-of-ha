{
  self.lib.test.faultTests.services-etcd = {
    toh.test.clusters.node.amount = 3;
    toh.test.clusters.node.module =
      { config, pkgs, ... }:
      let
        etcd = config.services.etcd;
      in
      {
        toh.services.etcd.enable = true;
        toh.services.envoy.enable = true;

        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "test-etcd";
            runtimeInputs = [ pkgs.etcd ];
            text = ''
              etcdctl \
                --endpoints=${builtins.head etcd.listenClientUrls} \
                --cacert=${etcd.trustedCaFile} \
                --cert=${etcd.certFile} \
                --key=${etcd.keyFile} \
                "$@"
            '';
          })
        ];
      };

    toh.test.commands.enable = true;
    toh.test.commands.perNode = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-config-online.target", timeout=180)''
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
          command_node.fail("""
            curl \
              --cacert ${cacrt} \
              -f \
              ${clientUrl}/health
          """)
          command_node.succeed("test-etcd member list | grep -c 'started' | grep 3")
        ''
      )
    ];

    # NOTE: there is no client, so a node that stays writes and another
    # reads, and reads of etcd go through the quorum
    toh.test.commands.suffix =
      { lib, nodes, ... }:
      ''
        fault_each(
          None,
          [${
            builtins.concatStringsSep ", " (
              builtins.filter (name: lib.hasPrefix "node" name) (builtins.attrNames nodes)
            )
          }],
          "toh-config-online.target",
          "test-etcd endpoint health --cluster",
          lambda value: f"test-etcd put fault/{value} {value}",
          lambda value: f"test-etcd get --print-value-only fault/{value} | grep -x {value}",
        )
      '';
  };
}
