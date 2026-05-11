# TODO: convert firewall rules to nebula firewall rules
# TODO: disable all traffic from outside nebula

{
  toh.lib.nixosModules.services-nebula =
    {
      pkgs,
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.nebula;

      port = 4242;

      isLighthouseAndRelay = config.toh.meta.domains.machineSecret != null;

      machines = tohLib.serviceMachines "nebula";

      machinesWithDomain = builtins.filter (machine: machine.meta.domains.machineSecret != null) machines;

      machineIpsWithDomain = builtins.map (machine: machine.meta.network.ip) machinesWithDomain;
    in
    {
      options.toh.services = {
        nebula = {
          enable = lib.mkEnableOption "Nebula VPN";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = (builtins.length machinesWithDomain) != 0;
            message = "Nebula VPN requires at least one machine with domain to configure a lighthouse and relay";
          }
        ];

        networking.networkmanager.ensureProfiles.profiles.${config.toh.meta.network.interface} = {
          connection = {
            id = config.toh.meta.network.interface;
            type = "tun";
            autoconnect = true;
            interface-name = config.toh.meta.network.interface;
          };
          ipv4 = {
            address1 = "${config.toh.meta.network.ip}/${builtins.toString config.toh.meta.network.subnet.bits}";
            method = "manual";
          };
          ipv6 = {
            method = "ignore";
          };
        };

        environment.systemPackages = [
          config.services.nebula.networks.toh.package
        ];

        # NOTE: these values are not used but nix evaluates them
        services.nebula.networks.toh = {
          enable = true;
          isLighthouse = isLighthouseAndRelay;
          ca = config.sops.secrets."nebula-ca-public".path;
          cert = config.sops.secrets."nebula-public".path;
          key = config.sops.secrets."nebula-private".path;
        };

        systemd.services."nebula@toh" = {
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
            ExecStart = lib.mkForce "${pkgs.nebula}/bin/nebula -config /etc/nebula/config.d";
            Restart = lib.mkForce "always";
          };
        };
        systemd.targets.toh-network-online = {
          wantedBy = [ "nebula@toh.service" ];
          bindsTo = [ "nebula@toh.service" ];
          after = [ "nebula@toh.service" ];
        };
        networking.firewall.allowedUDPPorts = lib.mkIf isLighthouseAndRelay [
          port
        ];
        environment.etc."nebula/config.d/config.yaml".text = ''
          pki:
            ca: ${config.sops.secrets."nebula-ca-public".path}
            cert: ${config.sops.secrets."nebula-public".path}
            key: ${config.sops.secrets."nebula-private".path}
          listen:
            host: '[::]'
            port: ${if isLighthouseAndRelay then "4242" else "0"}
          static_map:
            cadence: 5m
            lookup_timeout: 10s
          handshakes:
            try_interval: 1s
          preferred_ranges: [ '192.168.0.0/16' ]
          firewall:
            outbound:
              - port: any
                proto: any
                host: any
            inbound:
              - port: any
                proto: any
                host: any
          tun:
            dev: ${config.toh.meta.network.interface}
          punchy:
            punch: true
            respond: true
          ${
            if isLighthouseAndRelay then
              ''
                lighthouse:
                  am_lighthouse: true
                relay:
                  am_relay: true
              ''
            else
              ''
                lighthouse:
                  hosts: [ "${builtins.concatStringsSep ''", "'' machineIpsWithDomain}" ]
                relay:
                  relays: [ "${builtins.concatStringsSep ''", "'' machineIpsWithDomain}" ]
              ''
          }
        '';

        programs.rust-motd.settings = lib.mkIf isLighthouseAndRelay {
          service_status = {
            "Nebula" = "nebula@toh";
          };
        };

        sops.secrets."nebula-ca-public" = {
          owner = "nebula-toh";
          group = "nebula-toh";
          mode = "0644";
        };
        sops.secrets."nebula-public" = {
          owner = "nebula-toh";
          group = "nebula-toh";
          mode = "0644";
        };
        sops.secrets."nebula-private" = {
          owner = "nebula-toh";
          group = "nebula-toh";
          mode = "0400";
        };
        sops.secrets."nebula-static-host-map" = {
          path = "/etc/nebula/config.d/static-host-map.yaml";
          owner = "nebula-toh";
          group = "nebula-toh";
          mode = "0400";
        };

        toh.cryl.machine.nebula = {
          generations = [
            {
              generator = "nebula-cert";
              arguments = {
                ca_private = "cluster/nebula-ca-private";
                ca_public = "cluster/nebula-ca-public";
                name = config.toh.meta.machine.name;
                ip = "${config.toh.meta.network.ip}/${builtins.toString config.toh.meta.network.subnet.bits}";
                private = "nebula-private";
                public = "nebula-public";
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "nebula-static-host-map";
                renew = true;
                listing = {
                  type = "map";
                  value = builtins.listToAttrs (
                    builtins.map (machine: {
                      name = "NEBULA_${lib.toUpper machine.name}_DOMAIN";
                      value = "external/${machine.meta.domains.machineSecret}";
                    }) machinesWithDomain
                  );
                };
                template =
                  let
                    staticHostMap = builtins.concatStringsSep ", " (
                      builtins.map (machine: ''
                        "${machine.meta.network.ip}": [
                          "{{{NEBULA_${lib.toUpper machine.name}_DOMAIN}}}:${builtins.toString port}"
                        ]
                      '') machinesWithDomain
                    );
                  in
                  ''
                    static_host_map: { ${staticHostMap} }
                  '';
              };
            }
          ];
        };

        toh.cryl.machine.nebula-ca = {
          generations = [
            {
              generator = "copy";
              arguments = {
                from = "cluster/nebula-ca-public";
                to = "nebula-ca-public";
              };
            }
          ];
        };

        toh.cryl.cluster.nebula-ca = {
          generations = [
            {
              generator = "nebula-ca";
              arguments = {
                name = "toh";
                private = "nebula-ca-private";
                public = "nebula-ca-public";
              };
            }
          ];
        };
      };
    };
}
