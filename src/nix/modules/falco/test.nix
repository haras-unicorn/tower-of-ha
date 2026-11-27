{ selfLib, ... }:

{
  # NOTE: containers cannot load the eBPF probe of falco, so this test runs
  # falco without a driver and only checks that its metrics reach the
  # network; services-falco-alerts covers the probe
  self.nixosTests.services-falco = selfLib.test.makeNixosTest (
    { machines, ... }:
    let
      falco = machines.machine;
    in
    {
      toh.test.tier = 1;
      containers.machine = {
        toh.services.falco.enable = true;
        services.falco.settings.engine.kind = "nodriver";
      };

      containers.client =
        { pkgs, ... }:
        {
          environment.systemPackages = [ pkgs.curl ];
        };

      toh.test.commands.suffix = ''
        machine.wait_for_unit("falco.service")
        client.wait_until_succeeds(
          "curl --silent --fail"
          " 'http://${falco.toh.meta.network.ip}:${builtins.toString falco.toh.services.falco.port}/metrics'"
          " | grep -F falcosecurity_falco_version_info",
          timeout=120,
        )
      '';
    }
  );

  # NOTE: a vm, because the probe needs a kernel of its own; reading
  # /etc/shadow matches a stock rule, and the match has to arrive in
  # alertmanager as an alert
  self.nixosTests.services-falco-alerts = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      alerts = (builtins.head machineList).toh.meta.alerts;
    in
    {
      toh.test.tier = 3;
      toh.test.kind = "vm";

      toh.test.clusters.node = {
        amount = 1;
        module =
          { pkgs, ... }:
          {
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.envoy.enable = true;
            toh.services.prometheus.enable = true;
            toh.services.alertmanager.enable = true;
            toh.services.alertmanager.matrix.enable = false;
            toh.services.falco.enable = true;

            environment.systemPackages = [
              pkgs.curl
              pkgs.jq
            ];
          };
      };

      toh.test.commands.suffix = ''
        node1.wait_for_unit("falco.service")
        node1.wait_until_succeeds(
          "cat /etc/shadow > /dev/null"
          " && curl --silent --fail --get '${alerts.url}/api/v2/alerts'"
          " --data-urlencode 'filter=alertname=\"FalcoRuleMatched\"'"
          " --data-urlencode 'filter=rule_name=\"Read sensitive file untrusted\"'"
          " | jq --exit-status 'length == 1'",
          timeout=600,
        )
      '';
    }
  );
}
