{ self, ... }:

{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-openssh = pkgs.tohPackages.testers.runToHTest {
        name = "services-openssh";
        nodes.machine = {
          imports = [
            self.nixosModules.services-openssh
          ];
        };
        toh.test.commands.suffix = ''
          machine.succeed("systemctl is-enabled sshd.service")
          machine.succeed("grep 'PermitRootLogin no' /etc/ssh/sshd_config")
          machine.succeed("grep 'PasswordAuthentication no' /etc/ssh/sshd_config")
          machine.succeed("grep 'KbdInteractiveAuthentication no' /etc/ssh/sshd_config")
        '';
      };

      checks.test-services-openssh-cli-command = pkgs.tohPackages.testers.runToHTest {
        name = "services-openssh-cli-command";
        toh.test.clusters.node.amount = 2;
        toh.test.clusters.node.module = {
          imports = [
            self.nixosModules.services-openssh
            self.nixosModules.services-cli
          ];
        };
        toh.test.commands.perNode = [
          ''
            command_node.wait_for_unit("sshd.service")
          ''
        ];
        toh.test.commands.suffix =
          { nodes, lib, ... }:
          ''
            node1.succeed("""
              su - ${lib.escapeShellArg nodes.node1.toh.host.user} \
                -c 'toh ssh command --host node1 cat /etc/hostname 2>/dev/null' | \
                grep -q node1
            """)
            node2.succeed("""
              su - ${lib.escapeShellArg nodes.node2.toh.host.user} \
                -c 'toh ssh command --host node2 cat /etc/hostname 2>/dev/null' | \
                grep -q node2
            """)
          '';
      };

      checks.test-services-openssh-cli-copy = pkgs.tohPackages.testers.runToHTest {
        name = "services-openssh-cli-copy";
        toh.test.clusters.node.amount = 2;
        toh.test.clusters.node.module = {
          imports = [
            self.nixosModules.services-openssh
            self.nixosModules.services-cli
          ];
        };
        toh.test.commands.perNode = [
          ''
            command_node.wait_for_unit("sshd.service")
          ''
        ];
        toh.test.commands.suffix =
          { nodes, lib, ... }:
          ''
            node1.succeed("""
              su - ${lib.escapeShellArg nodes.node1.toh.host.user} \
                -c "toh ssh copy node2:/etc/hostname ${
                  lib.escapeShellArg (nodes.node1.toh.host.home + "/hostname")
                } 2>/dev/null"
            """)
            node1.succeed("""
              cat ${lib.escapeShellArg (nodes.node1.toh.host.home + "/hostname")} | \
                grep -q node2
            """)
            node2.succeed("""
              su - ${lib.escapeShellArg nodes.node2.toh.host.user} \
                -c "toh ssh copy node1:/etc/hostname ${
                  lib.escapeShellArg (nodes.node2.toh.host.home + "/hostname")
                } 2>/dev/null"
            """)
            node2.succeed("""
              cat ${lib.escapeShellArg (nodes.node2.toh.host.home + "/hostname")} | \
                grep -q node1
            """)
          '';
      };
    };
}
