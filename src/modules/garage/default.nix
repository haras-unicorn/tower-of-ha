{
  toh.lib.nixosModules.services-garage =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.garage;

      anyMachines = tohLib.anyServiceMachines "garage";
      garageMachines = tohLib.serviceMachines "garage";
      numberOfMachines = builtins.length garageMachines;
      replicationFactor =
        if numberOfMachines == 1 then
          1
        else if numberOfMachines == 2 then
          2
        else
          3;

      s3Port = 3900;
      webPort = 3902;
      adminPort = 3903;
      rpcPort = 3901;

      owner = tohLib.garage.user;
      group = tohLib.garage.group;

      rpcSecret = config.toh.meta.sops.secrets."garage-rpc-secret".path;

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.garage.endpoint;

      webProxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.garage-web.endpoint;
    in
    {
      options.toh.services = {
        garage = {
          enable = lib.mkEnableOption "Garage S3 storage";

          capacityInMB = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1024;
            description = "Storage capacity in MB to assign to each garage node";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.s3 = {
            protocol = "s3";
            host = proxyAttrs.host;
            port = proxyAttrs.port;
            region = config.toh.meta.locality.region;
          };
        })
        (lib.mkIf cfg.enable {
          virtualisation.diskSize = 1024 * (cfg.capacityInMB + 16);

          environment.systemPackages = [
            pkgs.garage
            pkgs.s3cmd
          ];

          services.garage = {
            enable = true;
            package = pkgs.garage;

            extraEnvironment = {
              GARAGE_CONFIG_FILE = "/run/secrets/garage.toml";
              # NOTE: the layout version thing is very verbose
              RUST_LOG = "garage=warn,garage_rpc::layout::version=error";
            };

            settings = {
              replication_factor = replicationFactor;
              consistency_mode = "consistent";

              rpc_secret_file = rpcSecret;
              rpc_bind_addr = "${config.toh.meta.network.ip}:${builtins.toString rpcPort}";
              rpc_public_addr = "${config.toh.meta.network.ip}:${builtins.toString rpcPort}";

              s3_api = {
                api_bind_addr = "${config.toh.meta.network.ip}:${builtins.toString s3Port}";
                s3_region = config.toh.meta.locality.region;
                root_domain = ".${proxyAttrs.host}";
              };

              s3_web = {
                bind_addr = "${config.toh.meta.network.ip}:${builtins.toString webPort}";
                root_domain = ".${webProxyAttrs.host}";
              };

              admin = {
                api_bind_addr = "${config.toh.meta.network.ip}:${builtins.toString adminPort}";
                admin_token_file = config.toh.meta.sops.secrets."garage-admin-token".path;
              };
            };
          };

          networking.firewall.allowedTCPPorts = [
            s3Port
            webPort
            adminPort
            rpcPort
          ];

          systemd.services.garage-config = {
            description = "Garage config file generation";
            wantedBy = [ "garage.service" ];
            before = [ "garage.service" ];
            unitConfig.ConditionPathExists = config.toh.meta.sops.secrets."garage-node-key".path;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = lib.getExe (
              pkgs.tohPackages.writeNushellApplication {
                name = "garage-config";
                text = ''
                  open -r ${config.toh.meta.sops.secrets."garage-node-key".path}
                    | decode hex
                    | save -fr /run/secrets/garage-node-key-decoded
                  chown ${owner}:${group} /run/secrets/garage-node-key-decoded
                  chmod 0400 /run/secrets/garage-node-key-decoded

                  open -r ${config.toh.meta.sops.secrets."garage-node-id".path}
                    | decode hex
                    | save -fr /run/secrets/garage-node-id-decoded
                  chown ${owner}:${group} /run/secrets/garage-node-id-decoded
                  chmod 0400 /run/secrets/garage-node-id-decoded

                  mkdir "${config.services.garage.settings.metadata_dir}"
                  chown ${owner}:${group} "${config.services.garage.settings.metadata_dir}"
                  chmod 0750 "${config.services.garage.settings.metadata_dir}"
                  (ln -sf
                    /run/secrets/garage-node-key-decoded
                    "${config.services.garage.settings.metadata_dir}/node_key")
                  (ln -sf
                    /run/secrets/garage-node-id-decoded
                    "${config.services.garage.settings.metadata_dir}/node_key.pub")

                  open -r ${config.toh.meta.sops.secrets."garage-bootstrap-peers".path} /etc/garage.toml
                    | str join "\n"
                    | save -fr /run/secrets/garage.toml
                  chown ${owner}:${group} /run/secrets/garage.toml
                  chmod 600 /run/secrets/garage.toml
                '';
              }
            );
          };

          systemd.services.garage = {
            serviceConfig = {
              DynamicUser = lib.mkForce false;
              User = lib.mkForce owner;
              Group = lib.mkForce group;
            };
            wantedBy = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
            after = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
            requires = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
          };

          systemd.targets.toh-s3-online = {
            wantedBy = [ "garage.service" ];
            bindsTo = [ "garage.service" ];
            after = [ "garage.service" ];
          };

          programs.rust-motd.settings.service_status.Garage = "garage";

          toh.meta.services.garage = {
            endpoint.tcp = {
              port = s3Port;
              layer7Protocol = "s3";
            };
            health.endpoint.http = {
              port = adminPort;
              path = "/health";
            };
          };

          toh.meta.services.garage-web = {
            endpoint.http = {
              port = webPort;
            };
            health.endpoint.http = {
              port = adminPort;
              path = "/health";
            };
          };

          toh.meta.sops.secrets."garage-rpc-secret" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."garage-admin-token" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."garage-node-key" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."garage-node-id" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.sops.secrets."garage-bootstrap-peers" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.cryl.machine = [
            {
              garage = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-rpc-secret";
                      to = "garage-rpc-secret";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-admin-token";
                      to = "garage-admin-token";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-node-key-${config.toh.meta.machine.name}";
                      to = "garage-node-key";
                    };
                  }
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/garage-node-id-${config.toh.meta.machine.name}";
                      to = "garage-node-id";
                    };
                  }
                ];
              };
            }
            {
              "garage-bootstrap-peers" = {
                generations = [
                  {
                    generator = "mustache";
                    arguments = {
                      name = "garage-bootstrap-peers";
                      renew = true;
                      listing = {
                        type = "map";
                        value = builtins.listToAttrs (
                          builtins.map (machine: {
                            name = "NODE_ID_${lib.toUpper machine.name}";
                            value = "cluster/garage-node-id-${machine.name}";
                          }) garageMachines
                        );
                      };
                      template =
                        let
                          peers = lib.concatMapStringsSep "\n" (
                            machine:
                            "\""
                            + "{{{NODE_ID_${lib.toUpper machine.name}}}}"
                            + "@${machine.meta.network.ip}"
                            + ":${builtins.toString rpcPort}"
                            + "\","
                          ) garageMachines;
                        in
                        ''
                          bootstrap_peers = [
                            ${tohLib.strings.indentTail "  " peers}
                          ]
                        '';
                    };
                  }
                ];
              };
            }
          ];

          toh.meta.cryl.cluster = [
            {
              garage = {
                generations = [
                  {
                    generator = "script";
                    arguments = {
                      name = "garage-rpc-secret-script";
                      renew = true;
                      text = "openssl rand -hex 32 | save -f garage-rpc-secret";
                    };
                  }
                  {
                    generator = "key";
                    arguments = {
                      name = "garage-admin-token";
                    };
                  }
                ];
              };
            }
          ]
          ++ builtins.map (machine: {
            "garage-node-${machine.name}" = {
              generations = [
                {
                  generator = "script";
                  arguments = {
                    name = "garage-node-key-${machine.name}-script";
                    renew = true;
                    text = ''
                      let init = openssl genpkey -algorithm ed25519
                      let private = $init | openssl pkey -outform DER | tail -c 32
                      let public = $init | openssl pkey -pubout -outform DER | tail -c 32
                      let key = $private | bytes add --end $public | encode hex
                      let id = $public | encode hex
                      $key | save -f garage-node-key-${machine.name}
                      $id | save -f garage-node-id-${machine.name}
                    '';
                  };
                }
              ];
            };
          }) garageMachines;

          toh.services.garage.createUserGroup = true;

          toh.services.garage.users.admin = {
            user = owner;
            group = group;
            installSecrets = true;
          };
        })
      ];
    };
}
