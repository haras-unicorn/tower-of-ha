{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.test-services-garage = pkgs.tohPackages.testers.runToHTest {
        name = "services-garage";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.programs.cli.enable = true;
            toh.services.coredns.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.garage.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-s3-online.target", timeout=300)''
          ''command_node.succeed("toh s3 admin ls s3://admin")''
          (
            node:
            let
              name = node.toh.meta.machine.name;
            in
            [
              ''command_node.succeed("echo ${name} > ${name}-up")''
              ''command_node.succeed("toh s3 admin put ${name}-up s3://admin/${name}")''
            ]
          )
          (
            { nodea, ... }:
            builtins.concatMap (
              node:
              let
                name = node.toh.meta.machine.name;
              in
              [
                ''command_node.succeed("toh s3 admin get s3://admin/${name} ${name}-down")''
                ''command_node.succeed("cat ${name}-down | grep -q ${name}")''
              ]
            ) nodea
          )
        ];
      };
    };
}
