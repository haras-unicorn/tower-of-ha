{ self, config, ... }:

let
  subnetConfig = config.toh.network.subnet;
in
{

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-nebula-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-nebula-disabled";
        toh.test.disabledService.enable = true;
        toh.test.disabledService.name = "nebula@toh.service";

        toh.test.disabledService.module = {
          imports = [ self.nixosModules.services-nebula ];
          toh.nebula.enable = false;
        };
      };

      checks.test-services-nebula-mesh =
        let
          vlan = 1;
          vlanString = builtins.toString vlan;

          addressOffset = 10;
          addressPrefix = "192.168.${vlanString}";

          amount = 5;

          # NOTE: first we want the non-lighthouse nodes to
          # try to connect to the lighthouse
          lighthouseNumber = amount;
          lighthouseNumberString = builtins.toString lighthouseNumber;
          lighthouseNebulaAddress = "${subnetConfig.prefix}.${lighthouseNumberString}";
          isLighthouse = config: config.toh.test.clusters.number == lighthouseNumber;

          lighthouseAddressNumber = addressOffset + lighthouseNumber;
          lighthouseAddressNumberString = builtins.toString lighthouseAddressNumber;
          lighthouseAddress = "${addressPrefix}.${lighthouseAddressNumberString}";

          lighthousePort = 4242;
          lighthousePortString = builtins.toString lighthousePort;
        in
        pkgs.tohPackages.testers.runToHTest {
          name = "services-nebula-mesh";

          toh.test.cryl.cluster.nebula = {
            generations = [
              {
                generator = "yaml";
                arguments = {
                  name = "nebula-lighthouse";
                  value = {
                    static_host_map.${lighthouseNebulaAddress} = [
                      "${lighthouseAddress}:${lighthousePortString}"
                    ];
                    lighthouse.am_lighthouse = true;
                    relay.am_relay = true;
                    punchy = {
                      punch = true;
                      respond = true;
                    };
                  };
                };
              }
              {
                generator = "yaml";
                arguments = {
                  name = "nebula-non-lighthouse";
                  value = {
                    static_host_map.${lighthouseNebulaAddress} = [
                      "${lighthouseAddress}:${lighthousePortString}"
                    ];
                    lighthouse.hosts = [ lighthouseNebulaAddress ];
                    relay.relays = [ lighthouseNebulaAddress ];
                    punchy = {
                      punch = true;
                      respond = true;
                    };
                  };
                };
              }
            ];
            exports = [
              {
                exporter = "copy";
                arguments = {
                  from = "nebula-lighthouse";
                  to = "${self.lib.cryl.directories.cluster}/nebula-lighthouse";
                };
              }
              {
                exporter = "copy";
                arguments = {
                  from = "nebula-non-lighthouse";
                  to = "${self.lib.cryl.directories.cluster}/nebula-non-lighthouse";
                };
              }
            ];
          };

          toh.test.clusters.node.amount = amount;
          toh.test.clusters.node.module =
            { lib, config, ... }:
            let
              addressNumber = addressOffset + config.toh.test.clusters.number;
              addressNumberString = builtins.toString addressNumber;
              address = "192.168.${vlanString}.${addressNumberString}";

              nebulaAddressNumber = config.toh.test.clusters.number;
              nebulaAddressNumberString = builtins.toString nebulaAddressNumber;
              nebulaAddress = "${subnetConfig.prefix}.${nebulaAddressNumberString}";
            in
            {
              imports = [
                self.nixosModules.services-nebula
              ];

              toh.test.network.enable = false;
              virtualisation.vlans = [ vlan ];
              # NOTE: mkBefore because we want to override the default one
              networking.interfaces.eth1.ipv4.addresses = lib.mkBefore [
                {
                  inherit address;
                  prefixLength = 24;
                }
              ];

              toh.host.ip = nebulaAddress;
              toh.host.interface = "toh";

              toh.nebula.enableLighthouseAndRelay = isLighthouse config;
              # NOTE: otherwise it opens the port on all hosts
              services.nebula.networks.toh.listen.port = lib.mkIf (isLighthouse config) lighthousePort;
            };

          toh.test.commands.enable = true;
          toh.test.commands.perNode = [
            ''command_node.wait_for_unit("network-online.target")''
            ''command_node.wait_for_unit("nebula@toh.service")''
            ''command_node.wait_until_succeeds("ip link show toh")''
            ''command_node.succeed("test -f /etc/nebula/config.d/config.yaml")''
            (
              node:
              if isLighthouse node then
                ''
                  command_node.succeed(
                    "grep -q 'am_lighthouse: true' /etc/nebula/config.d/lighthouse.yaml"
                  )
                  command_node.succeed(
                    "grep -q 'port: ${lighthousePortString}' /etc/nebula/config.d/config.yaml"
                  )
                  command_node.succeed("iptables -L -n | grep -q '${lighthousePortString}'")
                ''
              else
                ''
                  command_node.succeed(
                    "grep -q 'port: 0' /etc/nebula/config.d/config.yaml"
                  )
                  command_node.fail("iptables -L -n | grep -q '${lighthousePortString}'")
                ''
            )
            (node: ''
              command_node.succeed(
                "ip addr show toh | grep -q '${node.toh.host.ip}'"
              )
            '')
            (
              { nodea, ... }:
              builtins.map (other: ''
                command_node.wait_until_succeeds("ping -c 3 ${other.toh.host.ip}", timeout=10)
              '') nodea
            )
          ];
        };

      checks.test-services-nebula-relay = pkgs.tohPackages.testers.runToHTest {
        name = "services-nebula-relay";

        toh.test.cryl.cluster.nebula = {
          generations = [
            {
              generator = "yaml";
              arguments = {
                name = "nebula-lighthouse";
                value = {
                  static_host_map."${subnetConfig.prefix}.1" = [
                    "192.168.1.10:4242"
                    "192.168.2.10:4242"
                  ];
                  lighthouse.am_lighthouse = true;
                  relay.am_relay = true;
                  punchy = {
                    punch = true;
                    respond = true;
                  };
                };
              };
            }
            {
              generator = "yaml";
              arguments = {
                name = "nebula-non-lighthouse";
                value = {
                  static_host_map."${subnetConfig.prefix}.1" = [
                    "192.168.1.10:4242"
                    "192.168.2.10:4242"
                  ];
                  lighthouse.hosts = [ "${subnetConfig.prefix}.1" ];
                  relay.relays = [ "${subnetConfig.prefix}.1" ];
                  punchy = {
                    punch = true;
                    respond = true;
                  };
                };
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "nebula-lighthouse";
                to = "${self.lib.cryl.directories.cluster}/nebula-lighthouse";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "nebula-non-lighthouse";
                to = "${self.lib.cryl.directories.cluster}/nebula-non-lighthouse";
              };
            }
          ];
        };

        nodes = {
          relay = {
            imports = [
              self.nixosModules.services-nebula
            ];

            toh.test.network.enable = false;
            virtualisation.vlans = [
              1
              2
            ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.10";
                prefixLength = 24;
              }
            ];
            networking.interfaces.eth2.ipv4.addresses = [
              {
                address = "192.168.2.10";
                prefixLength = 24;
              }
            ];

            toh.host.ip = "${subnetConfig.prefix}.1";
            toh.host.interface = "toh";

            toh.nebula.enableLighthouseAndRelay = true;
          };

          node1 = {
            imports = [
              self.nixosModules.services-nebula
            ];

            toh.test.network.enable = false;
            virtualisation.vlans = [ 1 ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.20";
                prefixLength = 24;
              }
            ];

            toh.host.ip = "${subnetConfig.prefix}.11";
            toh.host.interface = "toh";

            toh.nebula.enableLighthouseAndRelay = false;
          };

          node2 = {
            imports = [
              self.nixosModules.services-nebula
            ];

            toh.test.network.enable = false;
            virtualisation.vlans = [ 2 ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.2.20";
                prefixLength = 24;
              }
            ];

            toh.host.ip = "${subnetConfig.prefix}.12";
            toh.host.interface = "toh";

            toh.nebula.enableLighthouseAndRelay = false;
          };
        };

        toh.test.commands.suffix = ''
          relay.wait_for_unit("network-online.target")
          node1.wait_for_unit("network-online.target")
          node2.wait_for_unit("network-online.target")

          relay.wait_for_unit("nebula@toh.service")
          node1.wait_for_unit("nebula@toh.service")
          node2.wait_for_unit("nebula@toh.service")

          relay.wait_until_succeeds("ip link show toh")
          node1.wait_until_succeeds("ip link show toh")
          node2.wait_until_succeeds("ip link show toh")

          relay.succeed("test -f /etc/nebula/config.d/config.yaml")
          relay.succeed("grep -q 'am_relay: true' /etc/nebula/config.d/lighthouse.yaml")

          node1.succeed("test -f /etc/nebula/config.d/config.yaml")
          node1.succeed("test -f /etc/nebula/config.d/lighthouse.yaml")
          node1.succeed("grep -q '${subnetConfig.prefix}.1' /etc/nebula/config.d/lighthouse.yaml")

          node2.succeed("test -f /etc/nebula/config.d/config.yaml")
          node2.succeed("test -f /etc/nebula/config.d/lighthouse.yaml")
          node2.succeed("grep -q '${subnetConfig.prefix}.1' /etc/nebula/config.d/lighthouse.yaml")

          relay.succeed("iptables -L -n | grep -q '4242'")
          node1.fail("iptables -L -n | grep -q '4242'")
          node2.fail("iptables -L -n | grep -q '4242'")

          relay.succeed("ip addr show toh | grep -q '${subnetConfig.prefix}.1'")
          node1.succeed("ip addr show toh | grep -q '${subnetConfig.prefix}.11'")
          node2.succeed("ip addr show toh | grep -q '${subnetConfig.prefix}.12'")

          node1.succeed("ping -c 3 192.168.1.10")
          node2.succeed("ping -c 3 192.168.2.10")
          relay.succeed("ping -c 3 192.168.1.20")
          relay.succeed("ping -c 3 192.168.2.20")

          node1.succeed("ping -c 3 ${subnetConfig.prefix}.1")
          node2.succeed("ping -c 3 ${subnetConfig.prefix}.1")
          relay.succeed("ping -c 3 ${subnetConfig.prefix}.11")
          relay.succeed("ping -c 3 ${subnetConfig.prefix}.12")

          node1.succeed("ping -c 3 ${subnetConfig.prefix}.12")
          node2.succeed("ping -c 3 ${subnetConfig.prefix}.11")

          node1.fail("ping -c 1 192.168.2.10 || ping -c 1 192.168.2.20")
          node2.fail("ping -c 1 192.168.1.10 || ping -c 1 192.168.1.20")
        '';
      };
    };
}
