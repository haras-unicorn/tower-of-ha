{ selfLib, ... }:

# NOTE: the client is both sides of the proxy here, it offers a service and
# reaches it back through the proxy, like an app that other machines call

# NOTE: the backends are one test server on several ports, and the handler
# answers with the port a request came in on, so the answer says which
# backend the proxy picked

{
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

      defaultPort = 443;

      routePorts = {
        prefix = 8441;
        regex = 8442;
        # NOTE: the two routes that take the same path, named so that going
        # by name would put the second before the first, which only the
        # priority does the other way round
        named = 8443;
        ranked = 8444;
      };

      routedPath = "/routed";
      regexPath = "/regex/[0-9]+";
      rankedPath = "/ranked";

      clientMeta = machines.client.toh.meta;
      proxyAttrs = selfLib.services.endpoint.toAttrs clientMeta.proxies.${app}.endpoint;

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
        { path, port }:
        ''client.wait_until_succeeds("contract-proxy ${path} | grep -qx ${builtins.toString port}", timeout=60)'';
    in
    {
      options.toh.test.contracts.proxy = selfLib.test.contract.options "proxy" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${proxyAttrs.host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                proxy = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.${app}.endpoint;

                contract = pkgs.writeShellApplication {
                  name = "contract-proxy";
                  runtimeInputs = [
                    pkgs.curl
                    pkgs.util-linux
                  ];
                  text = ''
                    exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      curl --fail --silent --show-error \
                        "https://${proxy.host}:${builtins.toString proxy.port}''${1:-}"
                  '';
                };
              in
              {
                toh.test.http = {
                  enable = true;
                  domains = [ proxy.host ];
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
          })
          {
            toh.test.commands.suffix = ''
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
            '';
          }
        ]
      );
    };
}
