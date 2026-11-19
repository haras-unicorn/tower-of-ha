{ selfLib, ... }:

# NOTE: the mesh layout of the vpn contract: every node is on one vlan and
# reaches every other node through the vpn

{
  self.lib.test.testModules.contracts-vpn-mesh =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.test.contracts.vpn;

      vlan = 1;
      vlanString = builtins.toString vlan;

      # NOTE: with virtualisation.vlans the test framework adds its own
      # address next to the one picked here, and udp replies then leave
      # from an address the peer did not dial
      vlanInterface = {
        inherit vlan;
        assignIP = false;
      };

      addressOffset = 10;
      addressPrefix = "192.168.${vlanString}";

      amount = cfg.servers;

      subnetConfig = config.toh.test.network.subnet;

      controllerNumber = amount;
      enableController = config: config.toh.test.clusters.number == controllerNumber;

      controllerAddressNumber = addressOffset + controllerNumber;
      controllerAddressNumberString = builtins.toString controllerAddressNumber;
      controllerAddress = "${addressPrefix}.${controllerAddressNumberString}";

      controllerZone = "test.toh";
      controllerDomain = "controller.${controllerZone}";
      controllerDomainSecret = "controller-domain";

      dnsAddress = addressPrefix + "." + builtins.toString (addressOffset + 32);
    in
    {
      config = lib.mkIf (cfg.enable && cfg.network == "mesh") (
        lib.mkMerge [
          (selfLib.test.ofKind config.toh.test.kind {
            dns = {
              virtualisation.interfaces.eth1 = vlanInterface;
              networking.interfaces.eth1.ipv4.addresses = [
                {
                  address = dnsAddress;
                  prefixLength = 24;
                }
              ];

              toh.meta.network.ip = dnsAddress;
              toh.meta.network.interface = "eth1";
            };
          })
          {
            toh.test.network.enable = false;

            toh.test.dns.enable = true;
            toh.test.dns.zones = {
              ${controllerZone} = {
                ${controllerDomain} = controllerAddress;
              };
            };

            toh.test.cryl.cluster = [
              {
                mesh = {
                  generations = [
                    {
                      generator = "text";
                      arguments = {
                        name = controllerDomainSecret;
                        text = controllerDomain;
                      };
                    }
                  ];
                };
              }
            ];

            toh.test.clusters.node.amount = amount;
            toh.test.clusters.node.module =
              { lib, config, ... }:
              let
                addressNumber = addressOffset + config.toh.test.clusters.number;
                addressNumberString = builtins.toString addressNumber;
                address = "192.168.${vlanString}.${addressNumberString}";

                meshAddressNumber = config.toh.test.clusters.number;
                meshAddressNumberString = builtins.toString meshAddressNumber;
                meshAddress = "${subnetConfig.prefix}.${meshAddressNumberString}";
              in
              {
                imports = [ cfg.server ];

                virtualisation.interfaces.eth1 = vlanInterface;
                networking.interfaces.eth1.ipv4.addresses = [
                  {
                    inherit address;
                    prefixLength = 24;
                  }
                ];
                networking.nameservers = lib.mkForce [ dnsAddress ];

                toh.meta.network.ip = meshAddress;
                toh.meta.network.interface = "toh";
                toh.meta.domains.machineSecret = lib.mkIf (enableController config) controllerDomainSecret;
              };

            toh.test.commands.enable = true;
            toh.test.commands.perNodeInCluster.node = [
              ''command_node.wait_for_unit("network-online.target")''
              ''command_node.wait_until_succeeds("ip link show toh")''
              (node: ''
                command_node.wait_until_succeeds(
                  "ip addr show toh | grep -q '${node.toh.meta.network.ip}'"
                )
              '')
              (
                { machineList, ... }:
                builtins.map (other: ''
                  command_node.wait_until_succeeds("ping -c 3 ${other.toh.meta.network.ip}", timeout=60)
                '') machineList
              )
            ];
          }
        ]
      );
    };
}
