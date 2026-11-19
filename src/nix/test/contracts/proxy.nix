{ selfLib, ... }:

# NOTE: the client is both sides of the proxy here, it offers a service and
# reaches it back through the proxy, like an app that other machines call

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
      value = "works";

      clientMeta = machines.client.toh.meta;
      proxyAttrs = selfLib.services.endpoint.toAttrs clientMeta.proxies.${app}.endpoint;
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
                        "https://${proxy.host}:${builtins.toString proxy.port}"
                  '';
                };
              in
              {
                toh.test.http = {
                  enable = true;
                  domains = [ proxy.host ];
                  handler = ''
                    response = "${value}"
                  '';
                };

                toh.meta.services.${app}.endpoint.https = {
                  port = config.toh.test.http.httpsPort;
                };

                toh.pki.installCa = true;

                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-proxy | grep -qx ${value}", timeout=300)
            '';
          }
        ]
      );
    };
}
