{ selfLib, ... }:

let
  server = {
    toh.services.etcd.enable = true;
    toh.services.coredns.enable = true;
    toh.services.envoy.enable = true;
    toh.services.node-exporter.enable = true;
    toh.services.prometheus.enable = true;
  };
in
{
  self.lib.test.testModules.contracts-metrics-prometheus = selfLib.test.contract.implementation {
    capability = "metrics";
    implementation = "prometheus";
    inherit server;
  };

  self.nixosTests.contracts-metrics-prometheus = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    toh.test.contracts.metrics = {
      enable = true;
      implementation.prometheus = { };
    };
  };

  # NOTE: every copy collects every machine, so a query without merging
  # would count each machine once per copy; the count has to stay right
  # after one copy stops, which Thanos Query covers from the others
  self.nixosTests.services-prometheus = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      metrics = (builtins.head machineList).toh.meta.metrics;
      machines = builtins.toString (builtins.length machineList);
    in
    {
      toh.test.tier = 1;
      toh.test.clusters.node = {
        amount = 3;
        module = server;
      };

      toh.test.commands.suffix = ''
        import json
        import urllib.parse

        def count(machine, job):
          query = urllib.parse.quote(f'count(up{{job="{job}"}} == 1)')
          status, output = machine.execute(
            f"curl --silent --fail '${metrics.url}/api/v1/query?query={query}&dedup=true'"
          )
          if status != 0:
            return None
          result = json.loads(output)["data"]["result"]
          return result[0]["value"][1] if result else None

        def counts_all(machine, job):
          def done(last_try):
            found = count(machine, job)
            if last_try:
              assert found == "${machines}", f"{job}: {found} machines up"
            return found == "${machines}"

          retry(done, timeout_seconds=300)

        for job in [ "node", "envoy", "prometheus", "thanos-query" ]:
          counts_all(node1, job)

        node1.succeed("systemctl stop prometheus.service thanos-sidecar.service")
        counts_all(node2, "node")
      '';
    }
  );
}
