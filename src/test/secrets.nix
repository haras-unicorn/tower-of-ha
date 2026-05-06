{ inputs, ... }:

{
  toh.lib.test.testModules.secrets =
    {
      lib,
      nodes,
      pkgs,
      config,
      nodea,
      ...
    }:
    let
      testConfig = config;
    in
    {
      imports = [
        inputs.cryl.testModules.default
      ];

      options.toh.test = {
        cryl = {
          cluster = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification);
            default = { };
            description = ''
              Specifications in attrs for uniqueness
              that will be collected into a shared specification
              for the test cluster
            '';
          };
        };
      };

      config = {
        cryl.enable = true;

        cryl.specifications.test-cluster = builtins.zipAttrsWith (_: builtins.concatLists) (
          builtins.attrValues config.toh.test.cryl.cluster
        );

        cryl.specifications.node-cluster = builtins.zipAttrsWith (_: builtins.concatLists) (
          builtins.attrValues (
            builtins.zipAttrsWith (_: builtins.head) (builtins.map (node: node.toh.cryl.cluster) nodea)
          )
        );

        cryl.extraArgs = [
          "--allow-script"
        ];
        cryl.sops.specifications = [
          "test-cluster"
          "node-cluster"
          "default"
        ];

        defaults =
          { config, ... }:
          {
            imports = [
              inputs.sops-nix.nixosModules.sops
            ];

            cryl.enable = true;

            cryl.specification = builtins.zipAttrsWith (_: builtins.concatLists) (
              builtins.attrValues config.toh.cryl.machine
            );

            toh.lib.secrets.directories = lib.mkForce {
              machines = "${testConfig.cryl.sops.package}";
              cluster = "${testConfig.cryl.sops.package}/cluster";
              external = "${testConfig.cryl.sops.package}/external";
            };
          };
      };
    };
}
