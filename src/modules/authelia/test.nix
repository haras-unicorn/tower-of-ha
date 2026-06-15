{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-authelia = pkgs.tohPackages.testers.runToHTest {
        name = "services-authelia";

        toh.test.clusters.node = {
          amount = 3;
          module =
            { config, ... }:
            {
              toh.programs.cli.enable = true;
              toh.services.haproxy.enable = true;
              toh.services.coredns.enable = true;
              toh.services.etcd.enable = true;
              toh.services.patroni.enable = true;
              toh.services.patroni.init.enable = true;
              toh.services.valkey.enable = true;
              toh.services.lldap.enable = true;
              toh.services.garage.enable = true;
              toh.services.maddy.enable = true;
              toh.services.authelia.enable = true;
              toh.meta.oidc.apps.test = {
                user = "test";
                group = "test";
                redirectUris = [ "https://${config.toh.meta.machine.name}.${config.toh.meta.domains.node}" ];
              };
            };
        };

        toh.test.commands.perNode = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-auth-oidc-initialized.target", timeout=300)''
          ''
            command_node.wait_until_succeeds("""
              curl -f https://authelia.service.toh/api/health | grep -q '"status":"OK"'
            """, timeout=60)
          ''
        ];
      };
    };
}
