{ selfLib, ... }:

{
  # NOTE: every share of free disk and memory is below 1, so with those
  # ratios the disk and memory alerts fire at once, and a unit that exits
  # with an error fires the unit alert
  self.nixosTests.services-node-exporter = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      first = builtins.head machineList;
      metrics = first.toh.meta.metrics;
      unit = "toh-check-fails.service";
    in
    {
      toh.test.tier = 1;
      toh.test.clusters.node = {
        amount = 3;
        module = {
          toh.services.etcd.enable = true;
          toh.services.coredns.enable = true;
          toh.services.envoy.enable = true;
          toh.services.prometheus.enable = true;
          toh.services.node-exporter = {
            enable = true;
            alerts = {
              diskFreeRatio = 1.0;
              memoryFreeRatio = 1.0;
              for = "0s";
            };
          };

          systemd.services.toh-check-fails = {
            script = "exit 1";
            serviceConfig.Type = "oneshot";
          };
        };
      };

      toh.test.commands.suffix = ''
        import json
        import urllib.parse

        def firing(machine, alert, labels):
          query = urllib.parse.quote(
            f'ALERTS{{alertname="{alert}",alertstate="firing"{labels}}}'
          )
          status, output = machine.execute(
            f"curl --silent --fail '${metrics.url}/api/v1/query?query={query}&dedup=true'"
          )
          return status == 0 and json.loads(output)["data"]["result"] != []

        def fires(machine, alert, labels=""):
          def done(last_try):
            found = firing(machine, alert, labels)
            if last_try:
              assert found, f"{alert} does not fire"
            return found

          retry(done, timeout_seconds=300)

        ${first.toh.meta.machine.name}.fail("systemctl start ${unit}")

        fires(${first.toh.meta.machine.name}, "DiskAlmostFull")
        fires(${first.toh.meta.machine.name}, "MemoryAlmostFull")
        fires(${first.toh.meta.machine.name}, "UnitFailed", ',name="${unit}"')
      '';
    }
  );
}
