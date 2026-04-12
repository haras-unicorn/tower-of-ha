{ self, ... }:

# TODO: convert firewall rules to nebula firewall rules
# TODO: disable all traffic from outside nebula
# TODO: service that checks if it can reach the lighthouse - something line nebula-pre.service and nebula-pre.target
# TODO: nebula-wait-online.service and toh-network-online.target

{
  toh.network.subnet = {
    prefix = "10.69.42";
    ip = "10.69.42.0";
    bits = 24;
    mask = "255.255.255.0";
  };

  flake.nixosModules.services-nebula =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      isLighthouseAndRelay = config.toh.nebula.enableLighthouseAndRelay;
    in
    {
      options.toh = {
        nebula = {
          enable = (lib.mkEnableOption "Nebula VPN") // {
            default = true;
          };

          enableLighthouseAndRelay = lib.mkEnableOption "Nebula VPN lighthouse and relay";
        };
      };

      config = lib.mkIf config.toh.nebula.enable {
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
            "toh-time-synchronized.target"
          ];
          after = [
            "network-online.target"
            "toh-time-synchronized.target"
          ];
          requires = [
            "network-online.target"
            "toh-time-synchronized.target"
          ];
          serviceConfig = {
            ExecStart = lib.mkForce "${pkgs.nebula}/bin/nebula -config /etc/nebula/config.d";
            ExecStartPost = lib.mkForce "${pkgs.bash}/bin/bash -c 'sleep 1 && ${pkgs.networkmanager}/bin/nmcli c up ${config.toh.host.interface} || true'";
            Restart = lib.mkForce "always";
          };
        };
        systemd.targets.toh-network-online = {
          wantedBy = [ "nebula@toh.service" ];
          bindsTo = [ "nebula@toh.service" ];
          after = [ "nebula@toh.service" ];
        };
        networking.firewall.allowedUDPPorts = lib.mkIf isLighthouseAndRelay [
          4242
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
            dev: ${config.toh.host.interface}
        '';

        networking.networkmanager.ensureProfiles.profiles.${config.toh.host.interface} = {
          connection = {
            id = config.toh.host.interface;
            type = "tun";
            autoconnect = true;
            interface-name = config.toh.host.interface;
          };
          ipv4 = {
            address1 = "${config.toh.host.ip}/${builtins.toString config.toh.network.subnet.bits}";
            method = "manual";
          };
          ipv6 = {
            method = "ignore";
          };
        };

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
        sops.secrets."nebula-lighthouse" = {
          path = "/etc/nebula/config.d/lighthouse.yaml";
          owner = "nebula-toh";
          group = "nebula-toh";
          mode = "0400";
        };

        toh.cryl.host.nebula = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/nebula-ca-private";
                to = "nebula-ca-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/nebula-ca-public";
                to = "nebula-ca-public";
              };
            }
            {
              importer = "copy";
              arguments =
                let
                  file = if isLighthouseAndRelay then "nebula-lighthouse" else "nebula-non-lighthouse";
                in
                {
                  from = "${self.lib.cryl.directories.cluster}/${file}";
                  to = "nebula-lighthouse";
                };
            }
          ];
          generations = [
            {
              generator = "nebula-cert";
              arguments = {
                ca_private = "nebula-ca-private";
                ca_public = "nebula-ca-public";
                name = config.toh.host.name;
                ip = "${config.toh.host.ip}/${builtins.toString config.toh.network.subnet.bits}";
                private = "nebula-private";
                public = "nebula-public";
              };
            }
          ];
        };

        toh.cryl.cluster.nebula = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/nebula-ca-private";
                to = "nebula-ca-private";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/nebula-ca-public";
                to = "nebula-ca-public";
                allow_fail = true;
              };
            }
          ];
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
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "nebula-ca-private";
                to = "${self.lib.cryl.directories.cluster}/nebula-ca-private";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "nebula-ca-public";
                to = "${self.lib.cryl.directories.cluster}/nebula-ca-public";
              };
            }
          ];
        };
      };
    };
}
