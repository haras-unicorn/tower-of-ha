{ selfLib, ... }:

# NOTE: the client declares an alert that always fires, and the alerts API
# has to hold it exactly once, although every collector of the cluster
# fires it

{
  self.lib.test.testModules.contracts-alerts =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.alerts;

      alert = "TohContract";

      clientMeta = machines.client.toh.meta;
    in
    {
      options.toh.test.contracts.alerts = selfLib.test.contract.options "alerts" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${clientMeta.alerts.host} = clientMeta.relays;
            client =
              { pkgs, ... }:
              {
                toh.meta.metrics.alerts.${alert} = {
                  expression = "vector(1)";
                  for = "0s";
                  summary = "The alerts contract always fires this";
                };

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
                "curl --silent --fail --get '${clientMeta.alerts.url}/api/v2/alerts'"
                " --data-urlencode 'filter=alertname=\"${alert}\"'"
                " | jq --exit-status 'length == 1'",
                timeout=300,
              )
            '';
          }
        ]
      );
    };
}
