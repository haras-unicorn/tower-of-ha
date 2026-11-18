{
  self.lib.test.testModules.clusters =
    { lib, config, ... }:
    let
      cfg = config.toh.test.clusters;

      clusters = builtins.map (
        name:
        cfg.${name}
        // {
          inherit name;
        }
      ) (builtins.filter (name: cfg.${name}.enable) (builtins.attrNames cfg));

      makeMachines =
        kind:
        builtins.listToAttrs (
          lib.flatten (
            builtins.map (
              cluster:
              builtins.map (number: {
                name = "${cluster.name}${builtins.toString number}";
                value =
                  { lib, ... }:
                  {
                    imports = [ cluster.module ];

                    options.toh.test = {
                      clusters = {
                        number = lib.mkOption {
                          type = lib.types.ints.unsigned;
                          description = "Cluster node number";
                        };
                      };
                    };

                    config = {
                      toh.test.clusters = {
                        number = number;
                      };
                    };
                  };
              }) (lib.range 1 cluster.amount)
            ) (builtins.filter (cluster: cluster.kind == kind) clusters)
          )
        );
    in
    {
      options.toh.test = {
        clusters = lib.mkOption {
          default = { };
          description = "Node clusters";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether to enable this node cluster";
                };

                module = lib.mkOption {
                  type = lib.types.deferredModule;
                  description = "Common cluster node module";
                };

                amount = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  description = "Amount of nodes";
                };

                kind = lib.mkOption {
                  type = lib.types.enum [
                    "container"
                    "vm"
                  ];
                  default = "vm";
                  description = ''
                    Whether the nodes are systemd-nspawn containers or QEMU VMs
                  '';
                };
              };
            }
          );
        };
      };

      config = {
        nodes = makeMachines "vm";
        containers = makeMachines "container";
      };
    };
}
