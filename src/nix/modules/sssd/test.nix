{ selfLib, ... }:

{
  self.nixosTests.services-sssd = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.clusters.node = {
      amount = 3;
      module =
        { pkgs, ... }:
        {
          toh.programs.cli.enable = true;
          toh.services.envoy.enable = true;
          toh.services.coredns.enable = true;
          toh.services.etcd.enable = true;
          toh.services.patroni.enable = true;
          toh.services.lldap.enable = true;
          toh.services.sssd.enable = true;

          # NOTE: a PAM service that asks only SSSD, since the stack of login
          # lets root in without a password in the test containers
          security.pam.services.sssd-check.text = ''
            auth required ${pkgs.sssd}/lib/security/pam_sss.so
            account required ${pkgs.sssd}/lib/security/pam_sss.so
          '';
        };
    };

    toh.test.commands.perNodeInCluster.node = [
      ''command_node.wait_until_succeeds("systemctl is-active toh-ldap-online.target", timeout=300)''
      ''command_node.wait_for_unit("sssd.service", timeout=120)''
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
      # NOTE: sssctl runs a PAM stack for the user, which asks LLDAP for the
      # password through SSSD
      (
        node:
        let
          name = node.toh.meta.machine.name;
        in
        ''
          output = command_node.succeed(
            "printf 'testpass123\\n' | sssctl user-checks user-${name} -a auth -s sssd-check 2>&1 || true"
          )
          assert "pam_authenticate for user [user-${name}]: Success" in output, output
          output = command_node.succeed(
            "printf 'wrong\\n' | sssctl user-checks user-${name} -a auth -s sssd-check 2>&1 || true"
          )
          assert "Authentication failure" in output, output
        ''
      )
      (
        { machineList, ... }:
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
        ) machineList
      )
    ];
  };
}
