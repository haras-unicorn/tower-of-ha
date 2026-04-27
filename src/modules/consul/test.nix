{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-consul-enabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-consul-enabled";
        nodes.machine = {
          toh.pki.enable = true;
          toh.services.consul.enable = true;
        };
        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.wait_for_unit("consul.service")
            machine.succeed("which consul")
            machine.succeed("systemctl is-enabled consul.service")
            machine.succeed("test -d /etc/consul")
            machine.succeed("test -d /etc/consul/certs")

            machine.wait_until_succeeds("""
              test -n "$(curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/status/leader)"
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/status/leader | \
                grep -Eq '[0-9]+.[0-9]+.[0-9]+.[0-9]+:[0-9]+'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/agent/self | \
                grep -q 'machine'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/catalog/datacenters | \
                grep -q 'toh'
            """)

            machine.succeed("iptables -L -n | grep -q '8500'")
            machine.succeed("iptables -L -n | grep -q '8300'")
            machine.succeed("iptables -L -n | grep -q '8301'")
            machine.succeed("iptables -L -n | grep -q '8302'")
            machine.succeed("iptables -L -n | grep -q '8503'")
          '';
      };

      checks.test-services-consul-services = pkgs.tohPackages.testers.runToHTest {
        name = "services-consul-services";
        nodes.machine = {
          toh.pki.enable = true;
          toh.services.consul.enable = true;

          toh.meta.services = [
            {
              name = "test-service";
              port = 8080;
              health = "http:///health";
            }
          ];
        };
        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.wait_for_unit("consul.service")
            machine.succeed("which consul")
            machine.succeed("systemctl is-enabled consul.service")

            machine.wait_until_succeeds("""
              test -n "$(curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/status/leader)"
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/status/leader | \
                grep -Eq '[0-9]+.[0-9]+.[0-9]+.[0-9]+:[0-9]+'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/catalog/service/test-service | \
                grep -q 'test-service'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/catalog/service/test-service | \
                grep -q 'test'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/catalog/service/test-service | \
                grep -q 'toh'
            """)
            machine.wait_until_succeeds("""
              curl -sk https://${nodes.machine.toh.meta.network.ip}:8500/v1/catalog/service/consul-ui | \
                grep -q 'consul-ui'
            """)
          '';
      };

      checks.test-services-consul-cluster = pkgs.tohPackages.testers.runToHTest {
        name = "services-consul-cluster";
        toh.test.clusters.node.amount = 3;
        toh.test.clusters.node.module = {
          toh.pki.enable = true;
          toh.services.consul.enable = true;
        };
        toh.test.commands.enable = true;
        toh.test.commands.perNode = [
          ''command_node.wait_for_unit("network-online.target")''
          ''command_node.wait_for_unit("consul.service")''
          ''command_node.succeed("systemctl is-enabled consul.service")''
          ''command_node.succeed("which consul")''
          (node: ''
            command_node.succeed("grep '${node.toh.meta.machine.name}' /etc/consul.json")
          '')
          (node: ''
            command_node.succeed("grep -q '${node.toh.meta.network.ip}' /etc/consul.json")
          '')
          (
            { nodea, ... }:
            builtins.map (other: ''
              command_node.succeed("grep -q '${other.toh.meta.network.ip}' /etc/consul.json")
            '') nodea
          )
          ''
            command_node.succeed("iptables -L -n | grep -q '8500'")
            command_node.succeed("iptables -L -n | grep -q '8300'")
            command_node.succeed("iptables -L -n | grep -q '8301'")
            command_node.succeed("iptables -L -n | grep -q '8302'")
          ''
          (node: ''
            command_node.wait_until_succeeds("""
              test -n "$(curl -sk https://${node.toh.meta.network.ip}:8500/v1/status/leader)"
            """)
          '')
          (node: ''
            command_node.wait_until_succeeds("""
              curl -sk https://${node.toh.meta.network.ip}:8500/v1/status/leader | \
                grep -Eq '[0-9]+.[0-9]+.[0-9]+.[0-9]+:[0-9]+'
            """)
          '')
          (
            { node, nodea, ... }:
            builtins.map (other: ''
              command_node.wait_until_succeeds("""
                curl -sk https://${node.toh.meta.network.ip}:8500/v1/agent/members | \
                  grep -Eq '${other.toh.meta.machine.name}'
              """)
            '') nodea
          )
        ];
        toh.test.commands.suffix = nodes: ''
          leader_output = node1.succeed("curl -sk https://${nodes.node1.toh.meta.network.ip}:8500/v1/status/leader")
          assert leader_output.strip() != '""', "Cluster should have elected a leader"
          assert "8300" in leader_output, "Leader should be listening on port 8300"
        '';
      };
    };
}
