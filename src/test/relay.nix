{
  toh.lib.test.testModules.relay =
    {
      config,
      lib,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.test.relay;

      subnetConfig = config.toh.test.network.subnet;

      controllerZone = "test.toh";
      controllerDomain = "controller.${controllerZone}";
      controllerDomainSecret = "controller-domain";
    in
    {
      options.toh.test = {
        relay = {
          enable = lib.mkEnableOption "ToH relay test";

          name = lib.mkOption {
            type = lib.types.str;
            description = "Test service config name";
          };

          unit = lib.mkOption {
            type = lib.types.str;
            description = "Test service unit name";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        name = "services-${cfg.name}-relay";

        toh.test.dns.enable = true;
        toh.test.dns.zones = {
          ${controllerZone} = {
            ${controllerDomain} = [
              "192.168.1.10"
              "192.168.2.10"
            ];
          };
        };

        toh.test.cryl.cluster.relay = {
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

        nodes = {
          dns = {
            toh.test.network.enable = false;
            virtualisation.vlans = [
              1
              2
            ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.30";
                prefixLength = 24;
              }
            ];
            networking.interfaces.eth2.ipv4.addresses = [
              {
                address = "192.168.2.30";
                prefixLength = 24;
              }
            ];
          };

          relay = {
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

            networking.nameservers = lib.mkForce [
              "192.168.1.30"
              "192.168.2.30"
            ];

            toh.meta.network.ip = "${subnetConfig.prefix}.1";
            toh.meta.network.interface = "toh";
            toh.meta.domains.machineSecret = controllerDomainSecret;

            toh.services.${cfg.name}.enable = true;
          };

          node1 = {
            toh.test.network.enable = false;

            virtualisation.vlans = [ 1 ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.1.20";
                prefixLength = 24;
              }
            ];

            networking.nameservers = lib.mkForce [ "192.168.1.30" ];

            toh.meta.network.ip = "${subnetConfig.prefix}.11";
            toh.meta.network.interface = "toh";

            toh.services.${cfg.name}.enable = true;
          };

          node2 = {
            toh.test.network.enable = false;

            virtualisation.vlans = [ 2 ];
            networking.interfaces.eth1.ipv4.addresses = [
              {
                address = "192.168.2.20";
                prefixLength = 24;
              }
            ];

            networking.nameservers = lib.mkForce [ "192.168.2.30" ];

            toh.meta.network.ip = "${subnetConfig.prefix}.12";
            toh.meta.network.interface = "toh";

            toh.services.${cfg.name}.enable = true;
          };
        };

        toh.test.commands.suffix = ''
          relay.wait_for_unit("network-online.target")
          node1.wait_for_unit("network-online.target")
          node2.wait_for_unit("network-online.target")

          relay.wait_for_unit("${cfg.unit}")
          node1.wait_for_unit("${cfg.unit}")
          node2.wait_for_unit("${cfg.unit}")

          relay.wait_until_succeeds("ip link show toh")
          node1.wait_until_succeeds("ip link show toh")
          node2.wait_until_succeeds("ip link show toh")

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
