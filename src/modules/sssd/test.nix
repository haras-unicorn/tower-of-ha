{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-sssd = pkgs.tohPackages.testers.runToHTest {
        name = "services-sssd";

        toh.test.clusters.node = {
          amount = 3;
          module = {
            toh.programs.cli.enable = true;
            toh.services.haproxy.enable = true;
            toh.services.coredns.enable = true;
            toh.services.etcd.enable = true;
            toh.services.patroni.enable = true;
            toh.services.patroni.init.enable = true;
            toh.services.lldap.enable = true;
            toh.services.sssd.enable = true;
          };
        };

        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_until_succeeds("systemctl is-active toh-auth-ldap-initialized.target", timeout=300)''
          ''command_node.wait_for_unit("sssd.service")''
          (
            node:
            let
              number = node.toh.meta.machine.index + 2000;
              numberStr = builtins.toString number;
              name = node.toh.meta.machine.name;
            in
            ''
              command_node.succeed("""
                toh ldap user add user-${name} testpass123 user-${name}@email.service.toh \
                  --uid-number ${numberStr} \
                  --gid-number ${numberStr} \
                  --home-directory /home/user-${name}
              """)
              command_node.wait_until_succeeds(
                "getent passwd user-${name} | grep -q user-${name}",
                timeout=30
              )
              command_node.succeed("id user-${name}")
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
                command_node.wait_until_succeeds(
                  "getent passwd user-${name} | grep -q user-${name}",
                  timeout=30
                )
                command_node.succeed("id user-${name}")
              ''
            ) nodea
          )
        ];
      };
    };
}
