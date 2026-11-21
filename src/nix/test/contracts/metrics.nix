{ selfLib, ... }:

# NOTE: the client serves a metric of its own and asks for it at the query
# address, so the metric has to be collected from a machine that runs no
# collector and come back through the proxy

{
  self.lib.test.testModules.contracts-metrics =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.metrics;

      app = selfLib.test.contract.app;
      metric = "toh_contract_value";
      value = "1";
      port = 9500;

      clientMeta = machines.client.toh.meta;
    in
    {
      options.toh.test.contracts.metrics = selfLib.test.contract.options "metrics" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${clientMeta.metrics.host} = clientMeta.relays;
            client =
              { pkgs, ... }:
              {
                toh.test.http = {
                  enable = true;
                  ssl = false;
                  httpPort = port;
                  handler = ''
                    content_type = "text/plain; version=0.0.4"
                    response = "${metric} ${value}\n"
                  '';
                };

                toh.meta.metrics.targets.${app} = { inherit port; };

                toh.pki.installCa = true;

                environment.systemPackages = [
                  pkgs.curl
                  pkgs.jq
                ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds(
                "curl --silent --fail '${clientMeta.metrics.url}/api/v1/query?query=${metric}'"
                " | jq --exit-status '.data.result[0].value[1] == \"${value}\"'",
                timeout=300,
              )
            '';
          }
        ]
      );
    };
}
