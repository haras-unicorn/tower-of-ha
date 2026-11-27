{ lib, selfLib, ... }:

# NOTE: without balancing, the client is both sides of the proxy, it offers a
# service and reaches it back through the proxy, like an app that other
# machines call; the backends are one test server on several ports, and the
# handler answers with the port a request came in on, so the answer says which
# backend the proxy picked

# NOTE: with balancing, every server offers the service itself, the handler
# answers with the address of its server, and the client checks that the proxy
# spreads requests over every server and leaves out one that is down

let
  # NOTE: named <frontend>-<backend>-<health>, the protocols the proxy speaks
  # to the client, to the backend and to the health check of the backend
  balancingVariants = {
    http-http-http.endpoint.http = true;

    http-https-http.endpoint.https = true;

    http-http-tcp = {
      endpoint.http = true;
      health.tcp.ssl = false;
    };

    http-https-tcp = {
      endpoint.https = true;
      health.tcp.ssl = true;
    };

    tcp-terminate-tcp.endpoint.tcp.sslTermination = "terminate";

    tcp-re-encrypt-tcp.endpoint.tcp.sslTermination = "re-encrypt";

    tcp-passthrough-tcp.endpoint.tcp.sslTermination = "passthrough";

    tcp-terminate-http = {
      endpoint.tcp.sslTermination = "terminate";
      health.http = true;
    };

    tcp-re-encrypt-http = {
      endpoint.tcp.sslTermination = "re-encrypt";
      health.https = true;
    };

    tcp-passthrough-http = {
      endpoint.tcp.sslTermination = "passthrough";
      health.https = true;
    };
  };

  balancingSubmodule =
    { config, ... }:
    let
      protocol = builtins.head (builtins.attrNames config.endpoint);
      endpointAttrs = config.endpoint.${protocol};
    in
    {
      options = {
        endpoint = lib.mkOption {
          description = "The endpoint every server offers behind the proxy";
          type = lib.types.attrTag {
            http = lib.mkOption {
              type = lib.types.bool;
              description = "A plain HTTP backend";
            };
            https = lib.mkOption {
              type = lib.types.bool;
              description = "An HTTPS backend";
            };
            tcp = lib.mkOption {
              description = "A TCP backend that speaks HTTP";
              type = lib.types.submodule {
                options.sslTermination = lib.mkOption {
                  type = lib.types.enum selfLib.services.sslTermination;
                  description = "Where TLS ends";
                };
              };
            };
          };
        };

        health = lib.mkOption {
          description = "The health check of every backend";
          default =
            if protocol == "tcp" then
              {
                tcp.ssl = builtins.elem endpointAttrs.sslTermination [
                  "passthrough"
                  "re-encrypt"
                ];
              }
            else
              { ${protocol} = true; };
          type = lib.types.attrTag {
            http = lib.mkOption {
              type = lib.types.bool;
              description = "A plain HTTP health check";
            };
            https = lib.mkOption {
              type = lib.types.bool;
              description = "An HTTPS health check";
            };
            tcp = lib.mkOption {
              description = "A TCP health check that only connects";
              type = lib.types.submodule {
                options.ssl = lib.mkOption {
                  type = lib.types.bool;
                  description = "Whether the check speaks TLS";
                };
              };
            };
          };
        };
      };
    };
in
{
  self.lib.test.proxyTests =
    implementation:
    let
      makeTest =
        balancing:
        selfLib.test.makeNixosTest {
          toh.test.tier = 1;
          toh.test.contracts.proxy = {
            enable = true;
            implementation.${implementation} = { };
            inherit balancing;
          };
        };
    in
    {
      "contracts-proxy-${implementation}" = makeTest null;
    }
    // lib.mapAttrs' (
      name: balancing: lib.nameValuePair "contracts-proxy-${implementation}-${name}" (makeTest balancing)
    ) balancingVariants;

  self.lib.test.testModules.contracts-proxy =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.proxy;

      app = selfLib.test.contract.app;

      clientMeta = machines.client.toh.meta;
      proxyAttrs = selfLib.services.endpoint.toAttrs clientMeta.proxies.${app}.endpoint;
      proxyUrl = "https://${proxyAttrs.host}:${builtins.toString proxyAttrs.port}";

      routing =
        let
          defaultPort = 443;

          routePorts = {
            prefix = 8441;
            regex = 8442;
            # NOTE: the two routes that take the same path, named so that
            # going by name would put the second before the first, which
            # only the priority does the other way round
            named = 8443;
            ranked = 8444;
          };

          routedPath = "/routed";
          regexPath = "/regex/[0-9]+";
          rankedPath = "/ranked";

          makeRoute =
            {
              port,
              path,
              priority ? 0,
            }:
            {
              endpoint.https = {
                inherit port;
                route = {
                  service = app;
                  inherit priority;
                  paths = [ path ];
                };
              };
            };

          reaches =
            {
              path,
              port,
              curlArgs ? "",
            }:
            ''client.wait_until_succeeds("contract-proxy ${path} ${curlArgs} | grep -qx ${builtins.toString port}", timeout=60)'';

          # NOTE: clients like Matrix servers name the port in the host
          # header even when it is the default one, and curl leaves it out
          hostWithPort = "--header 'Host: ${proxyAttrs.host}:${builtins.toString proxyAttrs.port}'";
        in
        {
          server = { };

          client =
            { pkgs, ... }:
            let
              contract = pkgs.writeShellApplication {
                name = "contract-proxy";
                runtimeInputs = [
                  pkgs.curl
                  pkgs.util-linux
                ];
                text = ''
                  exec setpriv --reuid=${app} --regid=${app} --init-groups \
                    curl --fail --silent --show-error "''${@:2}" \
                      "${proxyUrl}''${1:-}"
                '';
              };
            in
            {
              toh.test.http = {
                enable = true;
                domains = [ proxyAttrs.host ];
                httpsPort = defaultPort;
                extraHttpsPorts = builtins.attrValues routePorts;
                handler = ''
                  response = str(self.server.server_address[1])
                '';
              };

              toh.meta.services = {
                ${app}.endpoint.https.port = defaultPort;

                "${app}-prefix" = makeRoute {
                  port = routePorts.prefix;
                  path.prefix = routedPath;
                };

                "${app}-regex" = makeRoute {
                  port = routePorts.regex;
                  path.regex = regexPath;
                };

                "${app}-named-first" = makeRoute {
                  port = routePorts.named;
                  path.prefix = rankedPath;
                };

                "${app}-ranked-first" = makeRoute {
                  port = routePorts.ranked;
                  path.prefix = rankedPath;
                  priority = -1;
                };
              };

              toh.pki.installCa = true;

              environment.systemPackages = [ contract ];
            };

          commands = ''
            client.wait_until_succeeds("contract-proxy / | grep -qx ${builtins.toString defaultPort}", timeout=300)
            ${reaches {
              path = "${routedPath}/anything";
              port = routePorts.prefix;
            }}
            ${reaches {
              path = "/regex/123";
              port = routePorts.regex;
            }}
            ${reaches {
              path = "/regex/123abc";
              port = defaultPort;
            }}
            ${reaches {
              path = "${rankedPath}/anything";
              port = routePorts.ranked;
            }}
            ${reaches {
              path = "/";
              port = defaultPort;
              curlArgs = hostWithPort;
            }}
            ${reaches {
              path = "${routedPath}/anything";
              port = routePorts.prefix;
              curlArgs = hostWithPort;
            }}
          '';
        };

      balancing =
        let
          protocol = builtins.head (builtins.attrNames cfg.balancing.endpoint);
          endpointAttrs = cfg.balancing.endpoint.${protocol};
          healthProtocol = builtins.head (builtins.attrNames cfg.balancing.health);
          healthAttrs = cfg.balancing.health.${healthProtocol};

          ssl =
            if protocol == "tcp" then endpointAttrs.sslTermination != "terminate" else protocol == "https";

          httpPort = 80;
          httpsPort = 81;
          backendPort = if ssl then httpsPort else httpPort;

          healthPath = "/health";

          # NOTE: enough requests that a proxy that spreads them evenly or at
          # random reaches every server, and the retry covers the bad luck
          fetches = cfg.servers * 3;
          startTimeout = 300;
          changeTimeout = 120;

          serverNames = builtins.filter (lib.hasPrefix "server") (builtins.attrNames machines);
          downName = builtins.head serverNames;

          pythonSet =
            names:
            "set([ ${
              lib.concatMapStringsSep ", " (name: ''"${machines.${name}.toh.meta.network.ip}"'') names
            } ])";
        in
        {
          server =
            { config, ... }:
            {
              toh.test.http = {
                enable = true;
                inherit ssl httpPort httpsPort;
                domains = [ proxyAttrs.host ];
                handler = ''
                  if self.path == "${healthPath}":
                    response = "OK"
                  else:
                    response = "${config.toh.meta.network.ip}"
                '';
              };

              toh.meta.services.${app} = {
                endpoint.${protocol} = {
                  port = backendPort;
                }
                // lib.optionalAttrs (protocol == "tcp") {
                  inherit (endpointAttrs) sslTermination;
                };
                health.endpoint.${healthProtocol} = {
                  port = backendPort;
                }
                // lib.optionalAttrs (healthProtocol == "tcp") {
                  inherit (healthAttrs) ssl;
                }
                // lib.optionalAttrs (healthProtocol != "tcp") {
                  path = healthPath;
                };
              };
            };

          client =
            { pkgs, ... }:
            {
              toh.pki.installCa = true;
              environment.systemPackages = [ pkgs.curl ];
            };

          commands = ''
            def proxy_reaches(expected, what, timeout):
              def reached(last_try):
                addresses = set()
                for _ in range(${builtins.toString fetches}):
                  status, output = client.execute("curl --silent --fail ${proxyUrl}")
                  if status == 0:
                    addresses.add(output.strip())
                if last_try:
                  assert addresses == expected, f"{what}: {addresses} != {expected}"
                return addresses == expected

              retry(reached, timeout_seconds=timeout)

            ${lib.concatMapStringsSep "\n" (
              name: ''${name}.wait_for_unit("http.service", timeout=120)''
            ) serverNames}

            proxy_reaches(${pythonSet serverNames}, "Spreading at start failed", ${builtins.toString startTimeout})

            ${downName}.succeed("systemctl stop http.service")
            proxy_reaches(${pythonSet (builtins.tail serverNames)}, "Leaving out a stopped backend failed", ${builtins.toString changeTimeout})

            ${downName}.succeed("systemctl start http.service")
            proxy_reaches(${pythonSet serverNames}, "Taking back a started backend failed", ${builtins.toString changeTimeout})
          '';
        };

      picked = if cfg.balancing == null then routing else balancing;
    in
    {
      options.toh.test.contracts.proxy = selfLib.test.contract.options "proxy" cfg // {
        balancing = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule balancingSubmodule);
          default = null;
          description = ''
            Instead of routing, check that the proxy spreads the requests of
            a client over the servers that offer a service, and stops sending
            them to a server whose backend is down.
          '';
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${proxyAttrs.host} = clientMeta.relays;
            client = picked.client;
          })
          {
            toh.test.clusters.server.module = picked.server;
            toh.test.commands.suffix = picked.commands;
          }
        ]
      );
    };
}
