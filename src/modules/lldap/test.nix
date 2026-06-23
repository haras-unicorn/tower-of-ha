{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-lldap = pkgs.tohPackages.testers.runToHTest {
        name = "services-lldap";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.programs.cli.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.coredns.enable = true;
            toh.services.etcd.enable = true;
            toh.services.patroni.enable = true;
            toh.services.lldap.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-ldap-online.target", timeout=300)''
          ''command_node.wait_until_succeeds("curl -f https://lldap.service.toh/health", timeout=30)''
          ''
            command_node.succeed("""
              toh ldap search '(uid=admin)' | grep -q 'dn: uid=admin'
            """)
          ''
          (
            node:
            let
              name = node.toh.meta.machine.name;
            in
            ''
              command_node.succeed("""
                toh ldap user add user-${name} testpass123 user-${name}@email.service.toh
              """)
            ''
          )
          (
            { nodea, ... }:
            builtins.map (
              other:
              let
                name = other.toh.meta.machine.name;
              in
              ''
                command_node.succeed("""
                  toh ldap search '(uid=user-${name})' | grep -q 'dn: uid=user-${name}'
                """)
              ''
            ) nodea
          )
        ];
      };
    };
}
