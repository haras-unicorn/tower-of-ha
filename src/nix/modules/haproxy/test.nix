{ selfLib, ... }:

let
  makeProtocolTest =
    module:
    selfLib.test.makeNixosTest (
      {
        lib,
        machineList,
        config,
        ...
      }:
      let
        httpPort = 80;
        httpsPort = 81;

        amount = 3;
        fetchAmount = amount * 3;
        fetchAmountString = builtins.toString fetchAmount;
        routingTimeout = 120;
        routingTimeoutString = builtins.toString routingTimeout;

        ips = lib.concatMapStringsSep ", " (node: ''"${node.toh.meta.network.ip}"'') machineList;
        downNode = builtins.head machineList;
        downNodeName = downNode.toh.meta.machine.name;
        upNode = builtins.head (builtins.tail machineList);
        upNodeName = upNode.toh.meta.machine.name;
        urlFromNode =
          node:
          let
            endpointAttrs = selfLib.services.endpoint.toAttrs upNode.toh.meta.proxies.http.endpoint;
          in
          "https://${endpointAttrs.host}:${builtins.toString endpointAttrs.port}";
        remainingIps = lib.concatMapStringsSep ", " (n: ''"${n.toh.meta.network.ip}"'') (
          builtins.filter (node: node.toh.meta.machine.name != downNodeName) machineList
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
                        type = lib.types.enum selfLib.services.sslTermination;
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
              { config, ... }:
              let
                proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.http.endpoint;
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
            node_ips = set([ ${ips} ])
            remaining_ips = set([ ${remainingIps} ])

            def routes_to(machine, url, expected, what):
              def routed(last_try):
                ips = set()
                for _ in range(${fetchAmountString}):
                  status, output = machine.execute(f"curl -s {url}")
                  if status == 0:
                    ips.add(output.strip())
                if last_try:
                  assert ips == expected, f"{what}: {ips} != {expected}"
                return ips == expected

              retry(routed, timeout_seconds=${routingTimeoutString})
          '';

          toh.test.commands.perNodeInCluster.node = [
            ''command_node.wait_for_unit("coredns.service")''
            ''command_node.wait_for_unit("haproxy.service")''
            ''command_node.wait_for_unit("http.service")''
            (node: ''
              routes_to(command_node, "${urlFromNode node}", node_ips, "Routing at start failed")
            '')
          ];

          toh.test.commands.suffix = ''
            ${downNodeName}.succeed("systemctl stop http.service")
            routes_to(${upNodeName}, "${urlFromNode upNode}", remaining_ips, "Routing after stop failed")

            ${downNodeName}.succeed("systemctl start http.service")
            routes_to(${upNodeName}, "${urlFromNode upNode}", node_ips, "Routing after restart failed")
          '';
        };
      }
    );
in
{
  self.lib.test.testModules.contracts-proxy-haproxy = selfLib.test.contract.implementation {
    capability = "proxy";
    implementation = "haproxy";
    server = {
      toh.services.coredns.enable = true;
      toh.services.haproxy.enable = true;
    };
  };

  self.nixosTests.contracts-proxy-haproxy = selfLib.test.makeNixosTest {
    toh.test.contracts.proxy = {
      enable = true;
      implementation.haproxy = { };
    };
  };

  # NOTE: <frontend>-<backend>-<health>
  self.nixosTests.services-haproxy-http-http-http = makeProtocolTest {
    toh.test.haproxy.endpoint.http = true;
  };

  self.nixosTests.services-haproxy-http-https-http = makeProtocolTest {
    toh.test.haproxy.endpoint.https = true;
  };

  self.nixosTests.services-haproxy-http-http-tcp = makeProtocolTest {
    toh.test.haproxy.endpoint.http = true;
    toh.test.haproxy.health.endpoint.tcp.ssl = false;
  };

  self.nixosTests.services-haproxy-http-https-tcp = makeProtocolTest {
    toh.test.haproxy.endpoint.https = true;
    toh.test.haproxy.health.endpoint.tcp.ssl = true;
  };

  self.nixosTests.services-haproxy-tcp-terminate-tcp = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "terminate";
  };

  self.nixosTests.services-haproxy-tcp-re-encrypt-tcp = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "re-encrypt";
  };

  self.nixosTests.services-haproxy-tcp-passthrough-tcp = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "passthrough";
  };

  self.nixosTests.services-haproxy-tcp-terminate-http = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "terminate";
    toh.test.haproxy.health.endpoint.http = true;
  };

  self.nixosTests.services-haproxy-tcp-re-encrypt-http = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "re-encrypt";
    toh.test.haproxy.health.endpoint.https = true;
  };

  self.nixosTests.services-haproxy-tcp-passthrough-http = makeProtocolTest {
    toh.test.haproxy.endpoint.tcp.sslTermination = "passthrough";
    toh.test.haproxy.health.endpoint.https = true;
  };
}
