{ inputs, ... }:

{
  toh.lib.test.testModules.secrets =
    {
      lib,
      nodes,
      pkgs,
      config,
      nodea,
      tohLib,
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
          ++ [
            {
              exports = [
                {
                  exporter = "copy";
                  arguments = {
                    to = tohLib.secrets.directories.external;
                    listing.type = "flat";
                  };
                }
              ];
            }
          ]
        );

        cryl.specifications.node-cluster = builtins.zipAttrsWith (_: builtins.concatLists) (
          [
            {
              imports = [
                {
                  importer = "working-directory";
                  arguments = {
                    path = "external";
                  };
                }
                {
                  importer = "copy";
                  arguments = {
                    from = tohLib.secrets.directories.external;
                    listing.type = "flat";
                  };
                }
                {
                  importer = "working-directory";
                  arguments = {
                    path = "..";
                  };
                }
              ];
            }
          ]
          ++ builtins.attrValues (
            builtins.zipAttrsWith (_: builtins.head) (builtins.map (node: node.toh.cryl.cluster) nodea)
          )
          ++ [
            {
              exports = [
                {
                  exporter = "copy";
                  arguments = {
                    to = tohLib.secrets.directories.cluster;
                    listing.type = "flat";
                  };
                }
              ];
            }
          ]
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
              [
                {
                  imports = [
                    {
                      importer = "working-directory";
                      arguments = {
                        path = "external";
                      };
                    }
                    {
                      importer = "copy";
                      arguments = {
                        from = tohLib.secrets.directories.external;
                        listing.type = "flat";
                      };
                    }
                    {
                      importer = "working-directory";
                      arguments = {
                        path = "../cluster";
                      };
                    }
                    {
                      importer = "copy";
                      arguments = {
                        from = tohLib.secrets.directories.cluster;
                        listing.type = "flat";
                      };
                    }
                    {
                      importer = "working-directory";
                      arguments = {
                        path = "..";
                      };
                    }
                  ];
                }
              ]
              ++ builtins.attrValues config.toh.cryl.machine
              ++ [
                {
                  exports = [
                    {
                      exporter = "copy";
                      arguments = {
                        to = "${tohLib.secrets.directories.machines}/${config.toh.meta.machine.name}";
                        listing.type = "flat";
                      };
                    }
                    {
                      exporter = "working-directory";
                      arguments = {
                        path = "cluster";
                      };
                    }
                    {
                      exporter = "copy";
                      arguments = {
                        to = tohLib.secrets.directories.cluster;
                        listing.type = "flat";
                      };
                    }
                    {
                      exporter = "working-directory";
                      arguments = {
                        path = "..";
                      };
                    }
                  ];
                }
              ]
            );
            cryl.sops.secrets.flat = null;

            toh.meta.secrets.directories = {
              machines = "${testConfig.cryl.sops.package}/machines";
              cluster = "${testConfig.cryl.sops.package}/cluster";
              external = "${testConfig.cryl.sops.package}/external";
            };
          };
      };
    };
}
