{ selfLib, ... }:

{
  self.nixosModules.services-easytier.flake = true;
  self.nixosModules.services-easytier.value =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.easytier;

      port = 11010;
      network = "toh";
      instance = network;
      service = "easytier-${instance}";
      user = service;
      group = service;
      envSecret = service;

      machines = selfLib.cluster.serviceMachines config "easytier";

      machinesWithDomain = builtins.filter (machine: machine.meta.domains.machineSecret != null) machines;

      otherMachines = selfLib.cluster.otherServiceMachines config "easytier";

      otherMachinesWithDomain = builtins.filter (
        machine: machine.meta.domains.machineSecret != null
      ) otherMachines;

      hasDomain = config.toh.meta.domains.machineSecret != null;

      package = config.services.easytier.package;
    in
    {
      options.toh.services = {
        easytier = {
          enable = lib.mkEnableOption "EasyTier";

          stunServers = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            example = [ "stun.example.com:3478" ];
            description = ''
              STUN servers, as `host:port`, that EasyTier asks for its public
              address before punching through NAT. `null` keeps EasyTier's own
              list of public servers.
            '';
          };

          rpcPort = lib.mkOption {
            type = lib.types.port;
            default = 15888;
            description = ''
              Port of the RPC portal of EasyTier on localhost, which
              `easytier-cli` uses to read and change the node.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = (builtins.length machinesWithDomain) != 0;
            message = "Easytier VPN requires at least one machine with domain to configure a lighthouse and relay";
          }
        ];
        environment.systemPackages = [
          package
        ];

        services.easytier.enable = true;

        services.easytier.instances.${instance} = {
          environmentFiles = [
            config.toh.meta.sops.secrets.${envSecret}.path
          ];
          extraArgs = [
            (lib.mkIf hasDomain "--need-p2p")
            (lib.mkIf (!hasDomain) "--lazy-p2p")
            # NOTE: the portal can change the node, and easytier binds it to
            # every address unless told otherwise; the key of the config file
            # does not change that
            "--rpc-portal"
            "127.0.0.1:${builtins.toString cfg.rpcPort}"
          ];
          extraSettings = {
            network_identity = {
              network_name = network;
            };
            hostname = config.toh.meta.machine.name;
            ipv4 = "${config.toh.meta.network.ip}/${builtins.toString config.toh.meta.network.subnet.bits}";
            flags = {
              dev_name = "toh";
              private_mode = true;
            };
            listeners = [
              "udp://0.0.0.0:${builtins.toString port}"
            ];
          }
          // lib.optionalAttrs (cfg.stunServers != null) {
            stun_servers = cfg.stunServers;
          };
        };

        users.groups.${group} = { };

        users.users.${user} = {
          isSystemUser = true;
          group = group;
        };

        systemd.services.${service} = {
          wantedBy = [
            "network-online.target"
            "nss-lookup.target"
            "toh-time-synchronized.target"
          ];
          after = [
            "network-online.target"
            "nss-lookup.target"
            "toh-time-synchronized.target"
          ];
          requires = [
            "network-online.target"
            "nss-lookup.target"
            "toh-time-synchronized.target"
          ];
          serviceConfig = {
            User = user;
            Group = group;
            CapabilityBoundingSet = "CAP_NET_ADMIN";
            AmbientCapabilities = "CAP_NET_ADMIN";
          };
        };

        systemd.targets.toh-network-online = {
          bindsTo = [ "${service}.service" ];
          wantedBy = [ "${service}.service" ];
          after = [ "${service}.service" ];
        };

        networking.firewall.allowedUDPPorts = lib.mkIf hasDomain [
          port
        ];

        # NOTE: only the machines with a domain open the port; the others
        # and the extra ports of hole punching are reached through the
        # connections easytier starts
        toh.meta.network.holePunchers = [ "easytier-core" ];

        programs.rust-motd.settings = {
          service_status = {
            EasyTier = service;
          };
        };

        toh.meta.sops.secrets.${envSecret} = {
          owner = user;
          group = group;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            easytier = {
              generations =
                (builtins.map (machine: {
                  generator = "copy";
                  arguments = {
                    from = "external/${machine.meta.domains.machineSecret}";
                    to = "easytier-${machine.name}-domain";
                  };
                }) otherMachinesWithDomain)
                ++ [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/easytier-network-secret";
                      to = "easytier-network-secret";
                    };
                  }
                ]
                ++ [
                  {
                    generator = "mustache";
                    arguments = {
                      name = envSecret;
                      renew = true;
                      listing = {
                        type = "map";
                        value =
                          let
                            peersVariables = builtins.listToAttrs (
                              builtins.map (machine: {
                                name = "EASYTIER_${lib.toUpper machine.name}_DOMAIN";
                                value = "easytier-${machine.name}-domain";
                              }) otherMachinesWithDomain
                            );
                          in
                          {
                            EASYTIER_NETWORK_SECRET = "easytier-network-secret";
                          }
                          // peersVariables;
                      };
                      template =
                        let
                          peersTemplate = builtins.concatStringsSep "," (
                            builtins.map (
                              machine: "udp://{{{EASYTIER_${lib.toUpper machine.name}_DOMAIN}}}:${builtins.toString port}"
                            ) otherMachinesWithDomain
                          );
                        in
                        ''
                          ${if peersTemplate == "" then "" else ''ET_PEERS="${peersTemplate}"''}
                          ET_NETWORK_SECRET="{{{EASYTIER_NETWORK_SECRET}}}"
                        '';
                    };
                  }
                ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            easytier = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "easytier-network-secret";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
