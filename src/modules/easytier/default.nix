{
  toh.lib.nixosModules.services-easytier =
    {
      pkgs,
      lib,
      tohLib,
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

      otherMachines = tohLib.otherServiceMachines "easytier";

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
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          package
        ];

        services.easytier.enable = true;
        services.easytier.package = pkgs.unstableTohPackages.easytier;

        services.easytier.instances.${instance} = {
          environmentFiles = [
            config.sops.secrets.${envSecret}.path
          ];
          extraArgs = [
            (lib.mkIf hasDomain "--need-p2p")
            (lib.mkIf (!hasDomain) "--lazy-p2p")
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

        programs.rust-motd.settings = {
          service_status = {
            EasyTier = service;
          };
        };

        sops.secrets.${envSecret} = {
          owner = user;
          group = group;
          mode = "0400";
        };

        toh.cryl.machine.easytier = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/easytier-network-secret";
                to = "easytier-network-secret";
              };
            }
          ]
          ++ (builtins.map (machine: {
            importer = "copy";
            arguments = {
              from = "${tohLib.secrets.directories.external}/${machine.meta.domains.machineSecret}";
              to = "easytier-${machine.name}-domain";
            };
          }) otherMachinesWithDomain);
          generations = [
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

        toh.cryl.cluster.easytier = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/easytier-network-secret";
                to = "easytier-network-secret";
                allow_fail = true;
              };
            }
          ];
          generations = [
            {
              generator = "key";
              arguments = {
                name = "easytier-network-secret";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "easytier-network-secret";
                to = "${tohLib.secrets.directories.cluster}/easytier-network-secret";
              };
            }
          ];
        };
      };
    };
}
