# TODO: dnssec and dnsovertls
# TODO: sort service hosts by and set low ttl
# so caching does not disrupt this order a lot
# if something goes down:
# 1. machine
# 2. rack
# 3. datacenter
# 4. region
# 5. other regions

{ selfLib, ... }:

{
  self.nixosModules.services-coredns.flake = true;
  self.nixosModules.services-coredns.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    let
      cfg = config.toh.services.coredns;
      machines = config.toh.meta.cluster.machineList;
      nodeDomain = config.toh.meta.domains.node;
      serviceDomain = config.toh.meta.domains.service;
      emailDomain = config.toh.meta.email.domain;

      otherCorednsMachines = selfLib.cluster.otherServiceMachines config "coredns";

      relayZones = lib.unique [
        serviceDomain
        emailDomain
      ];
      relaysDirectory = "/run/coredns-relays";
      relaysUser = "coredns-relays";

      makeLocalRelayZone = zone: ''
        ${zone} {
          bind 127.0.0.1
          file ${relaysDirectory}/${zone}.local.zone {
            reload ${builtins.toString cfg.relays.interval}s
          }
        }
      '';

      # NOTE: the zones twice, once for queries from this machine, which may
      # get its own relay at localhost, and once for the others, see
      # relays.nu; the zones for the others are loaded with auto, which
      # drops a zone once its file is gone and then refuses its queries, so
      # a machine that is cut off sends clients to another nameserver
      relayZonesConfig = ''
        ${builtins.concatStringsSep "\n" (builtins.map makeLocalRelayZone relayZones)}

        ${builtins.concatStringsSep " " relayZones} {
          bind ${config.toh.meta.network.ip}
          auto {
            directory ${relaysDirectory}/network ^(.*)\.zone$ {1}
            reload ${builtins.toString cfg.relays.interval}s
          }
        }
      '';
    in
    {
      options.toh.services = {
        coredns = {
          enable = lib.mkEnableOption "CoreDNS";

          forwarders = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              # NOTE: Cloudflare
              "1.1.1.1"
              "1.0.0.1"
              # NOTE: Google
              "8.8.8.8"
              "8.8.4.4"
            ];
            description = "Upstream DNS forwarders for external queries";
          };

          relays = {
            interval = lib.mkOption {
              type = lib.types.ints.positive;
              default = 2;
              description = ''
                Seconds between two health checks of every relay, after which
                the answers name only the relays that answered. While fewer
                than half of the relays answer, the machine is likely cut off,
                and it refuses the queries of other machines for the relay
                zones, so they ask another nameserver.
              '';
            };

            timeout = lib.mkOption {
              type = lib.types.ints.positive;
              default = 1;
              description = "Seconds a relay has to answer its health check.";
            };

            ttl = lib.mkOption {
              type = lib.types.ints.positive;
              default = 5;
              description = ''
                Seconds a client may keep an answer that names relays, so it
                stops using a relay that went down soon after.
              '';
            };
          };
        };
      };
      config = lib.mkMerge [
        (lib.mkIf (selfLib.cluster.anyServiceMachines config "coredns") {
          networking.networkmanager.dns = "none";
          networking.nameservers = builtins.map (machine: machine.meta.network.ip) otherCorednsMachines;
        })
        (lib.mkIf cfg.enable {
          networking.networkmanager.dns = "none";
          networking.nameservers = lib.mkBefore [ "127.0.0.1" ];

          networking.firewall.allowedUDPPorts = [ 53 ];
          networking.firewall.allowedTCPPorts = [ 53 ];

          toh.overlays = selfLib.cli.makeOverlays {
            name = "coredns-relays";
            runtimeInputs = (
              pkgs: [
                pkgs.curl
                pkgs.coreutils
                pkgs.systemd
              ]
            );
            textFile = ./relays.nu;
            textVariables = {
              TOH_COREDNS_RELAYS_ALL = builtins.toJSON config.toh.meta.relays;
              TOH_COREDNS_RELAYS_OWN_IP = config.toh.meta.network.ip;
              TOH_COREDNS_RELAYS_ZONES = builtins.toJSON relayZones;
              TOH_COREDNS_RELAYS_DIRECTORY = relaysDirectory;
              TOH_COREDNS_RELAYS_HEALTH_PORT = builtins.toString config.toh.meta.proxy.health.port;
              TOH_COREDNS_RELAYS_HEALTH_PATH = config.toh.meta.proxy.health.path;
              TOH_COREDNS_RELAYS_INTERVAL = builtins.toString cfg.relays.interval;
              TOH_COREDNS_RELAYS_TIMEOUT = builtins.toString cfg.relays.timeout;
              TOH_COREDNS_RELAYS_TTL = builtins.toString cfg.relays.ttl;
            };
          };

          systemd.services.coredns-relays = {
            description = "Zones of the relays that are up, for CoreDNS";
            wantedBy = [ "coredns.service" ];
            before = [ "coredns.service" ];
            after = [ "toh-network-online.target" ];
            wants = [ "toh-network-online.target" ];
            serviceConfig = {
              Type = "notify";
              NotifyAccess = "all";
              ExecStart = "${pkgs.tohPackages.coredns-relays}/bin/coredns-relays";
              Restart = "always";
              # NOTE: a user of its own and not a dynamic one, because systemd
              # hides the kept runtime directory of a dynamic user from other
              # users, and CoreDNS has to read the zones
              User = relaysUser;
              Group = relaysUser;
              RuntimeDirectory = builtins.baseNameOf relaysDirectory;
              RuntimeDirectoryMode = "0755";
              # NOTE: CoreDNS keeps reading the zones while this restarts
              RuntimeDirectoryPreserve = true;
              UMask = "0022";
            };
          };

          users.users.${relaysUser} = {
            isSystemUser = true;
            group = relaysUser;
          };
          users.groups.${relaysUser} = { };

          systemd.services.coredns = {
            requires = [ "coredns-relays.service" ];
            after = [ "coredns-relays.service" ];
          };

          services.coredns = {
            enable = true;
            config = ''
              ${nodeDomain} {
                bind 127.0.0.1
                bind ${config.toh.meta.network.ip}
                hosts {
                  ${builtins.concatStringsSep "\n" (
                    builtins.map (m: "${m.config.toh.meta.network.ip} ${m.name}.${nodeDomain}") machines
                  )}
                  fallthrough
                }
              }

              ${relayZonesConfig}

              . {
                bind 127.0.0.1
                bind ${config.toh.meta.network.ip}
                forward . ${builtins.concatStringsSep " " cfg.forwarders}
              }
            '';
          };
        })
      ];
    };
}
