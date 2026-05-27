{
  perSystem =
    { pkgs, lib, ... }:
    let
      makeProtocolTest =
        module:
        pkgs.tohPackages.testers.runToHTest (
          {
            lib,
            tohLib,
            nodea,
            nodes,
            config,
            ...
          }:
          let
            httpPort = 80;
            httpsPort = 81;

            amount = 3;
            fetchAmount = amount * 3;
            fetchAmountString = builtins.toString fetchAmount;

            ips = lib.concatMapStringsSep ", " (node: ''"${node.toh.meta.network.ip}"'') nodea;
            downNode = builtins.head nodea;
            downNodeName = downNode.toh.meta.machine.name;
            upNode = builtins.head (builtins.tail nodea);
            upNodeName = upNode.toh.meta.machine.name;
            urlFromNode =
              node:
              let
                endpointAttrs = upNode.toh.lib.services.endpoint.toAttrs upNode.toh.meta.proxies.http.endpoint;
              in
              "https://${endpointAttrs.host}:${builtins.toString endpointAttrs.port}";
            remainingIps = lib.concatMapStringsSep ", " (n: ''"${n.toh.meta.network.ip}"'') (
              builtins.filter (node: node.toh.meta.machine.name != downNodeName) nodea
            );

            cfg = config.toh.test.haproxy;
            protocol = builtins.head (builtins.attrNames cfg.endpoint);
            endpointAttrs = cfg.endpoint.${protocol};
            defaultHealthEndpoint =
              if protocol == "tcp" then
                {
                  tcp.ssl = builtins.elem endpointAttrs.sslTermination [
                    "passthrough"
                    "re-encrypt"
                  ];
                }
              else
                { ${protocol} = true; };
            healthProtocol = builtins.head (builtins.attrNames cfg.health.endpoint);
            healthEndpointAttrs = cfg.health.endpoint.${healthProtocol};
            ssl =
              if protocol == "tcp" then endpointAttrs.sslTermination != "terminate" else protocol == "https";
            sslAttrs =
              if protocol == "tcp" then
                {
                  sslTermination = endpointAttrs.sslTermination;
                }
              else
                {
                };
            healthSslAttrs =
              if healthProtocol == "tcp" then
                {
                  ssl = healthEndpointAttrs.ssl;
                }
              else
                {
                };
            healthHttpAttrs =
              lib.optionalAttrs
                (builtins.elem healthProtocol [
                  "http"
                  "https"
                ])
                {
                  path = "health";
                };
          in
          {
            imports = [ module ];

            options.toh.test = {
              haproxy = {
                endpoint = lib.mkOption {
                  type = lib.types.attrTag {
                    http = lib.mkOption {
                      type = lib.types.bool;
                    };
                    https = lib.mkOption {
                      type = lib.types.bool;
                    };
                    tcp = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          sslTermination = lib.mkOption {
                            type = lib.types.enum tohLib.services.sslTermination;
                          };
                        };
                      };
                    };
                  };
                };
                health.endpoint = lib.mkOption {
                  default = defaultHealthEndpoint;
                  type = lib.types.attrTag {
                    http = lib.mkOption {
                      type = lib.types.bool;
                    };
                    https = lib.mkOption {
                      type = lib.types.bool;
                    };
                    tcp = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          ssl = lib.mkOption {
                            type = lib.types.bool;
                          };
                        };
                      };
                    };
                  };
                };
              };
            };

            config = {
              toh.test.clusters.node = {
                inherit amount;
                module =
                  { config, tohLib, ... }:
                  let
                    proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.http.endpoint;
                  in
                  {
                    toh.services.coredns.enable = true;

                    toh.services.haproxy.enable = true;

                    toh.test.http = {
                      inherit httpPort httpsPort;
                      ssl = ssl;
                      enable = true;
                      domains = [ proxyAttrs.host ];
                      handler = ''
                        status_code = 200

                        if self.path == "/health":
                          response = "OK"
                        else:
                          response = "${config.toh.meta.network.ip}"
                      '';
                    };

                    toh.meta.services.http = {
                      endpoint.${protocol} = {
                        port = if ssl then httpsPort else httpPort;
                      }
                      // sslAttrs;
                      health.endpoint.${healthProtocol} = {
                        port = if ssl then httpsPort else httpPort;
                      }
                      // healthSslAttrs
                      // healthHttpAttrs;
                    };
                  };
              };

              toh.test.commands.prefix = ''
                import time

                node_ips = set([ ${ips} ])
                remaining_ips = set([ ${remainingIps} ])
              '';

              toh.test.commands.perNodeInCluster.node = [
                ''command_node.wait_for_unit("coredns.service")''
                ''command_node.wait_for_unit("haproxy.service")''
                ''command_node.wait_for_unit("http.service")''
                (node: ''
                  # NOTE: python is freaking slow
                  ${if node.toh.test.clusters.number == 1 then "time.sleep(10)" else ""}

                  ips = set([
                    command_node.succeed("curl -s ${urlFromNode node}").strip()
                    for _ in range(${fetchAmountString})
                  ])
                  assert ips == node_ips, f"{ips} != {node_ips}"
                '')
              ];

              toh.test.commands.suffix = ''
                ${downNodeName}.succeed("systemctl stop http.service")

                time.sleep(10)

                ips = set([
                  ${upNodeName}.succeed("curl -s ${urlFromNode upNode}").strip()
                  for _ in range(${fetchAmountString})
                ])
                assert ips == remaining_ips, f"Routing after stop failed: {ips} != {remaining_ips}"

                ${downNodeName}.succeed("systemctl start http.service")

                time.sleep(20)

                ips = set([
                  ${upNodeName}.succeed("curl -s ${urlFromNode upNode}").strip()
                  for _ in range(${fetchAmountString})
                ])
                assert ips == node_ips, f"Routing after restart failed: {ips} != {node_ips}"
              '';
            };
          }
        );
    in
    # NOTE: <frontend>-<backend>-<health>
    {
      checks.test-services-haproxy-http-http-http = makeProtocolTest {
        name = "services-haproxy-http-http-http";
        toh.test.haproxy.endpoint.http = true;
      };

      checks.test-services-haproxy-http-https-http = makeProtocolTest {
        name = "services-haproxy-http-https-http";
        toh.test.haproxy.endpoint.https = true;
      };

      checks.test-services-haproxy-http-http-tcp = makeProtocolTest {
        name = "services-haproxy-http-http-tcp";
        toh.test.haproxy.endpoint.http = true;
        toh.test.haproxy.health.endpoint.tcp.ssl = false;
      };

      checks.test-services-haproxy-http-https-tcp = makeProtocolTest {
        name = "services-haproxy-http-https-tcp";
        toh.test.haproxy.endpoint.https = true;
        toh.test.haproxy.health.endpoint.tcp.ssl = true;
      };

      checks.test-services-haproxy-tcp-terminate-tcp = makeProtocolTest {
        name = "services-haproxy-tcp-terminate-tcp";
        toh.test.haproxy.endpoint.tcp.sslTermination = "terminate";
      };

      checks.test-services-haproxy-tcp-re-encrypt-tcp = makeProtocolTest {
        name = "services-haproxy-tcp-re-encrypt-tcp";
        toh.test.haproxy.endpoint.tcp.sslTermination = "re-encrypt";
      };

      checks.test-services-haproxy-tcp-passthrough-tcp = makeProtocolTest {
        name = "services-haproxy-tcp-passthrough-tcp";
        toh.test.haproxy.endpoint.tcp.sslTermination = "passthrough";
      };

      checks.test-services-haproxy-tcp-terminate-http = makeProtocolTest {
        name = "services-haproxy-tcp-terminate-http";
        toh.test.haproxy.endpoint.tcp.sslTermination = "terminate";
        toh.test.haproxy.health.endpoint.http = true;
      };

      checks.test-services-haproxy-tcp-re-encrypt-http = makeProtocolTest {
        name = "services-haproxy-tcp-re-encrypt-http";
        toh.test.haproxy.endpoint.tcp.sslTermination = "re-encrypt";
        toh.test.haproxy.health.endpoint.https = true;
      };

      checks.test-services-haproxy-tcp-passthrough-http = makeProtocolTest {
        name = "services-haproxy-tcp-passthrough-http";
        toh.test.haproxy.endpoint.tcp.sslTermination = "passthrough";
        toh.test.haproxy.health.endpoint.https = true;
      };
    };
}
