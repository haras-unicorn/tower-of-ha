{
  toh.lib.test.testModules.mesh =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.test.mesh;

      vlan = 1;
      vlanString = builtins.toString vlan;

      addressOffset = 10;
      addressPrefix = "192.168.${vlanString}";

      amount = cfg.amount;

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
      options.toh.test = {
        mesh = {
          enable = lib.mkEnableOption "ToH mesh test";

          amount = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 5;
            description = "Amount of nodes to test with";
          };

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
        name = "services-${cfg.name}-mesh";

        toh.test.dns.enable = true;
        toh.test.dns.zones = {
          ${controllerZone} = {
            ${controllerDomain} = controllerAddress;
          };
        };

        nodes.dns =
          { lib, ... }:
          {
            toh.test.network.enable = false;

            virtualisation.vlans = [ vlan ];
            # NOTE: mkBefore because we want to override the default one
            networking.interfaces.eth1.ipv4.addresses = lib.mkBefore [
              {
                address = dnsAddress;
                prefixLength = 24;
              }
            ];

            toh.meta.network.ip = dnsAddress;
            toh.meta.network.interface = "eth1";
          };

        toh.test.cryl.cluster.mesh = {
          generations = [
            {
              generator = "text";
              arguments = {
                name = controllerDomainSecret;
                text = controllerDomain;
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = controllerDomainSecret;
                to = "${tohLib.secrets.directories.external}/${controllerDomainSecret}";
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

            meshAddressNumber = config.toh.test.clusters.number;
            meshAddressNumberString = builtins.toString meshAddressNumber;
            meshAddress = "${subnetConfig.prefix}.${meshAddressNumberString}";
          in
          {
            toh.test.network.enable = false;

            virtualisation.vlans = [ vlan ];
            # NOTE: mkBefore because we want to override the default one
            networking.interfaces.eth1.ipv4.addresses = lib.mkBefore [
              {
                inherit address;
                prefixLength = 24;
              }
            ];
            networking.nameservers = lib.mkForce [ dnsAddress ];

            toh.meta.network.ip = meshAddress;
            toh.meta.network.interface = "toh";
            toh.meta.domains.machineSecret = lib.mkIf (enableController config) controllerDomainSecret;

            toh.services.${cfg.name}.enable = true;
          };

        toh.test.commands.enable = true;
        toh.test.commands.perNodeInCluster.node = [
          ''command_node.wait_for_unit("network-online.target")''
          ''command_node.wait_for_unit("${cfg.unit}")''
          ''command_node.wait_until_succeeds("ip link show toh")''
          (node: ''
            command_node.succeed(
              "ip addr show toh | grep -q '${node.toh.meta.network.ip}'"
            )
          '')
          (
            { nodea, ... }:
            builtins.map (other: ''
              command_node.wait_until_succeeds("ping -c 3 ${other.toh.meta.network.ip}", timeout=10)
            '') nodea
          )
        ];
      };
    };
}
