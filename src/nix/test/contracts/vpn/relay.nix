{ selfLib, ... }:

# NOTE: the relay layout of the vpn contract: two homes behind NAT routers and
# a relay on the "internet" between them, the way people run a VPN from home:
#
#   node1 (vlan 1) - router1 \
#                              vlan 3: relay, dns
#   node2 (vlan 2) - router2 /
#
# In the proxy mode the routers drop traffic to each other, so the nodes can
# only talk through the relay. In the punch mode they can, so the nodes find
# each other through the relay and then punch through both NATs directly; the
# test waits until node1's pings to node2 leave towards router2 and then cuts
# the relay off.

{
  self.lib.test.testModules.contracts-vpn-relay =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.toh.test.contracts.vpn;

      subnetConfig = config.toh.test.network.subnet;

      controllerZone = "test.toh";
      controllerDomain = "controller.${controllerZone}";
      controllerDomainSecret = "controller-domain";

      internet = {
        relay = "192.168.3.10";
        dns = "192.168.3.30";
        router1 = "192.168.3.1";
        router2 = "192.168.3.2";
      };

      homes = {
        "1" = {
          router = "192.168.1.1";
          node = "192.168.1.20";
          otherRouter = internet.router2;
        };
        "2" = {
          router = "192.168.2.1";
          node = "192.168.2.20";
          otherRouter = internet.router1;
        };
      };

      stun = {
        listening-port = 3478;
        alt-listening-port = 3479;
      };

      useStun = cfg.stun && cfg.mode == "punch";

      stunServers = [
        "${internet.dns}:${builtins.toString stun.listening-port}"
        "${internet.dns}:${builtins.toString stun.alt-listening-port}"
      ];

      # NOTE: with virtualisation.vlans the test framework adds its own
      # address next to the one picked here, and udp replies then leave
      # from an address the peer did not dial
      vlanInterface = vlan: {
        inherit vlan;
        assignIP = false;
      };

      address = ip: [
        {
          address = ip;
          prefixLength = 24;
        }
      ];

      router =
        home:
        let
          homeConfig = homes.${home};
        in
        {
          virtualisation.interfaces.eth1 = vlanInterface (lib.toInt home);
          virtualisation.interfaces.eth2 = vlanInterface 3;
          networking.interfaces.eth1.ipv4.addresses = address homeConfig.router;
          networking.interfaces.eth2.ipv4.addresses = address internet."router${home}";

          networking.nat = {
            enable = true;
            internalInterfaces = [ "eth1" ];
            externalInterface = "eth2";
          };

          networking.firewall.extraCommands = lib.mkIf (cfg.mode == "proxy") ''
            iptables -I FORWARD 1 -d ${homeConfig.otherRouter} -j DROP
            iptables -I FORWARD 1 -s ${homeConfig.otherRouter} -j DROP
          '';
        };

      node =
        home:
        let
          homeConfig = homes.${home};
        in
        {
          imports = [ cfg.server ];

          virtualisation.interfaces.eth1 = vlanInterface (lib.toInt home);
          networking.interfaces.eth1.ipv4.addresses = address homeConfig.node;
          networking.defaultGateway = {
            address = homeConfig.router;
            interface = "eth1";
          };
          networking.nameservers = lib.mkForce [ internet.dns ];

          toh.meta.network.ip = "${subnetConfig.prefix}.1${home}";
          toh.meta.network.interface = "toh";
        };
    in
    {
      config = lib.mkIf (cfg.enable && cfg.network == "relay") (
        lib.mkMerge [
          {
            toh.test.contracts.vpn.stunServers = lib.mkIf useStun stunServers;

            toh.test.network.enable = false;

            toh.test.dns.enable = true;
            toh.test.dns.zones = {
              ${controllerZone} = {
                ${controllerDomain} = [ internet.relay ];
              };
            };

            toh.test.cryl.cluster = [
              {
                relay = {
                  generations = [
                    {
                      generator = "text";
                      arguments = {
                        name = controllerDomainSecret;
                        text = controllerDomain;
                      };
                    }
                  ];
                };
              }
            ];

          }
          (selfLib.test.ofKind config.toh.test.kind {
            dns = {
              virtualisation.interfaces.eth1 = vlanInterface 3;
              networking.interfaces.eth1.ipv4.addresses = address internet.dns;

              services.coturn = lib.mkIf useStun {
                enable = true;
                listening-ips = [ internet.dns ];
                inherit (stun) listening-port alt-listening-port;
                no-cli = true;
                no-tls = true;
                no-dtls = true;
                extraConfig = "stun-only";
              };
              networking.firewall.allowedUDPPorts = lib.mkIf useStun [
                stun.listening-port
                stun.alt-listening-port
              ];
            };

            relay = {
              imports = [ cfg.server ];

              virtualisation.interfaces.eth1 = vlanInterface 3;
              networking.interfaces.eth1.ipv4.addresses = address internet.relay;
              networking.nameservers = lib.mkForce [ internet.dns ];

              toh.meta.network.ip = "${subnetConfig.prefix}.1";
              toh.meta.network.interface = "toh";
              toh.meta.domains.machineSecret = controllerDomainSecret;
            };

            router1 = router "1";
            router2 = router "2";

            node1 = node "1";
            node2 = node "2";
          })
          {
            toh.test.commands.suffix = ''
              relay.wait_for_unit("network-online.target")
              node1.wait_for_unit("network-online.target")
              node2.wait_for_unit("network-online.target")

              relay.wait_until_succeeds("ip link show toh")
              node1.wait_until_succeeds("ip link show toh")
              node2.wait_until_succeeds("ip link show toh")

              relay.wait_until_succeeds("ip addr show toh | grep -q '${subnetConfig.prefix}.1'")
              node1.wait_until_succeeds("ip addr show toh | grep -q '${subnetConfig.prefix}.11'")
              node2.wait_until_succeeds("ip addr show toh | grep -q '${subnetConfig.prefix}.12'")

              node1.succeed("ping -c 3 ${internet.relay}")
              node2.succeed("ping -c 3 ${internet.relay}")
              relay.fail("ping -c 1 ${homes."1".node}")
              relay.fail("ping -c 1 ${homes."2".node}")
              node1.fail("ping -c 1 ${homes."2".node}")
              node2.fail("ping -c 1 ${homes."1".node}")

              node1.wait_until_succeeds("ping -c 1 ${subnetConfig.prefix}.1", timeout=60)
              node2.wait_until_succeeds("ping -c 1 ${subnetConfig.prefix}.1", timeout=60)
              relay.succeed("ping -c 3 ${subnetConfig.prefix}.11")
              relay.succeed("ping -c 3 ${subnetConfig.prefix}.12")

              node1.wait_until_succeeds("ping -c 1 ${subnetConfig.prefix}.12", timeout=60)
              node2.wait_until_succeeds("ping -c 1 ${subnetConfig.prefix}.11", timeout=60)
              node1.succeed("ping -c 3 ${subnetConfig.prefix}.12")
              node2.succeed("ping -c 3 ${subnetConfig.prefix}.11")
            ''
            + lib.optionalString (cfg.mode == "punch") ''

              node1.succeed("iptables -I OUTPUT 1 -d ${internet.router2} -p udp -m comment --comment toh-direct")
              node1.wait_until_succeeds("""
                count() { iptables -vnxL OUTPUT | awk '/toh-direct/ {print $1}'; }
                before=$(count)
                ping -c 5 -i 0.2 ${subnetConfig.prefix}.12 >/dev/null
                [ $(( $(count) - before )) -ge 5 ]
              """, timeout=90)

              relay.succeed("iptables -I INPUT 1 -p udp -j DROP")
              relay.succeed("iptables -I OUTPUT 1 -p udp -j DROP")
              node1.succeed("ping -c 3 ${subnetConfig.prefix}.12")
              node2.succeed("ping -c 3 ${subnetConfig.prefix}.11")
            '';
          }
        ]
      );
    };
}
