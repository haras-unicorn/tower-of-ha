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
            type = lib.types.listOf (
              lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification)
            );
            default = [ ];
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
          tohLib.lists.concatUniqueAttrValues config.toh.test.cryl.cluster
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
          ++ tohLib.lists.concatUniqueAttrValues (builtins.concatMap (node: node.toh.meta.cryl.cluster) nodea)
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
              ++ tohLib.lists.concatUniqueAttrValues config.toh.meta.cryl.machine
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

            sops.useSystemdActivation = true;
            sops.secrets = config.toh.meta.sops.secrets;

            toh.meta.sops.secrets.${config.toh.meta.secrets.keys.age} = {
              owner = "root";
              group = "root";
              mode = "0400";
            };

            systemd.services.sops-install-secrets = lib.mkIf config.toh.services.openbao.secrets.enable {
              requires = [ "openbao-age-key-fetch.service" ];
              after = [ "openbao-age-key-fetch.service" ];
            };

            systemd.services.openbao-age-key-shred = lib.mkIf config.toh.services.openbao.secrets.enable {
              wantedBy = [ "sops-install-secrets.service" ];
              after = [ "sops-install-secrets.service" ];
            };

            systemd.services.build-ca-bundle-and-p11-kit-trust = lib.mkIf config.toh.pki.installCa {
              requires = [ "sops-install-secrets.service" ];
              after = [ "sops-install-secrets.service" ];
            };

            systemd.targets.toh-secrets-initialized = lib.mkMerge [
              {
                wantedBy = [ "sops-install-secrets.service" ];
                bindsTo = [ "sops-install-secrets.service" ];
                after = [ "sops-install-secrets.service" ];
              }
              (lib.mkIf config.toh.pki.installCa {
                wantedBy = [ "build-ca-bundle-and-p11-kit-trust.service" ];
                bindsTo = [ "build-ca-bundle-and-p11-kit-trust.service" ];
                after = [ "build-ca-bundle-and-p11-kit-trust.service" ];
              })
              (lib.mkIf config.toh.services.openbao.secrets.enable {
                wantedBy = [
                  "openbao-age-key-fetch.service"
                  "openbao-age-key-shred.service"
                ];
                bindsTo = [
                  "openbao-age-key-fetch.service"
                  "openbao-age-key-shred.service"
                ];
                after = [
                  "openbao-age-key-fetch.service"
                ];
                before = [
                  "openbao-age-key-shred.service"
                ];
              })
            ];

            toh.meta.secrets.directories = {
              machines = "${testConfig.cryl.sops.package}/machines";
              cluster = "${testConfig.cryl.sops.package}/cluster";
              external = "${testConfig.cryl.sops.package}/external";
            };

            toh.meta.secrets.files = {
              age = config.sops.age.keyFile;
              sops = config.sops.defaultSopsFile;
              token = "${builtins.dirOf config.sops.age.keyFile}/${tohLib.secrets.files.token}";
              response = "${builtins.dirOf config.sops.age.keyFile}/${tohLib.secrets.files.response}";
              metadata = "${builtins.dirOf config.sops.age.keyFile}/${tohLib.secrets.files.metadata}";
              root = "${builtins.dirOf config.sops.age.keyFile}/${tohLib.secrets.files.root}";
            };
          };
      };
    };
}
