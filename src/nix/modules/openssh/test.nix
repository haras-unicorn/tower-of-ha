{ selfLib, ... }:

let
  cliCluster = {
    toh.test.clusters.node.amount = 2;
    toh.test.clusters.node.module = {
      toh.programs.cli.enable = true;
      toh.services.openssh.enable = true;
    };
    toh.test.commands.perNode = [
      ''
        command_node.wait_for_unit("sshd.service")
      ''
    ];
  };
in
{
  self.nixosTests.services-openssh = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    containers.machine = {
      toh.services.openssh.enable = true;
    };
    # NOTE: root login and password auth are forced by the test defaults
    toh.test.commands.suffix = ''
      machine.succeed("systemctl is-enabled sshd.service")
      machine.succeed("grep 'KbdInteractiveAuthentication no' /etc/ssh/sshd_config")
    '';
  };

  self.nixosTests.services-openssh-cli-command = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    imports = [ cliCluster ];
    toh.test.commands.suffix =
      { nodes, lib, ... }:
      ''
        node1.succeed("""
          su - ${lib.escapeShellArg nodes.node1.toh.meta.user.user} \
            -c 'toh ssh command --machine node2 cat /etc/hostname 2>/dev/null' | \
            grep -q node2
        """)
        node2.succeed("""
          su - ${lib.escapeShellArg nodes.node2.toh.meta.user.user} \
            -c 'toh ssh command --machine node1 cat /etc/hostname 2>/dev/null' | \
            grep -q node1
        """)
      '';
  };

  self.nixosTests.services-openssh-cli-copy = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    imports = [ cliCluster ];
    toh.test.commands.suffix =
      { nodes, lib, ... }:
      let
        copyTo = node: lib.escapeShellArg (node.toh.meta.user.home + "/hostname");
      in
      ''
        node1.succeed("""
          su - ${lib.escapeShellArg nodes.node1.toh.meta.user.user} \
            -c "toh ssh copy node2:/etc/hostname ${copyTo nodes.node1} 2>/dev/null"
        """)
        node1.succeed("cat ${copyTo nodes.node1} | grep -q node2")
        node2.succeed("""
          su - ${lib.escapeShellArg nodes.node2.toh.meta.user.user} \
            -c "toh ssh copy node1:/etc/hostname ${copyTo nodes.node2} 2>/dev/null"
        """)
        node2.succeed("cat ${copyTo nodes.node2} | grep -q node1")
      '';
  };
}
