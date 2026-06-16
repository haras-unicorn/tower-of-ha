{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.test-services-maddy = pkgs.tohPackages.testers.runToHTest {
        name = "services-maddy";

        toh.test.clusters.node = {
          amount = 3;
          module = { config, ... }: {
            toh.programs.cli.enable = true;
            toh.services.coredns.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.etcd.enable = true;
            toh.services.patroni.enable = true;
            toh.services.garage.enable = true;
            toh.services.lldap.enable = true;
            toh.services.maddy.enable = true;

            toh.meta.email.apps.test = {
              user = config.toh.meta.user.user;
              group = config.toh.meta.user.group;
            };
          };
        };

        # TODO: actually try sending and reading when himalaya in v2
        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-email-online.target", timeout=300)''
          ''command_node.succeed("toh email maddy envelope list")''
        ];
      };
    };
}
