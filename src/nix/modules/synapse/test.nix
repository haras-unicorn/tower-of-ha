{ selfLib, ... }:

let
  server = {
    toh.services.etcd.enable = true;
    toh.services.coredns.enable = true;
    toh.services.haproxy.enable = true;
    toh.services.patroni.enable = true;
    toh.services.cephfs.enable = true;
    toh.services.valkey.enable = true;
    toh.services.synapse.enable = true;
  };
in
{
  self.lib.test.testModules.contracts-chat-synapse = selfLib.test.contract.implementation {
    capability = "chat";
    implementation = "synapse";
    inherit server;
  };

  self.nixosTests.contracts-chat-synapse = selfLib.test.makeNixosTest {
    toh.test.contracts.chat = {
      enable = true;
      implementation.synapse = { };
    };
  };

  self.nixosTests.services-synapse = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      replication =
        selfLib.services.endpoint.toAttrs
          (builtins.head machineList).toh.meta.proxies."synapse-replication".endpoint;

      chat = selfLib.services.endpoint.toAttrs (builtins.head machineList)
        .toh.meta.proxies.synapse.endpoint;

      nodes = builtins.concatStringsSep ", " (
        builtins.map (
          machine:
          ''(${machine.toh.meta.machine.name}, "${machine.toh.meta.network.ip}", ${builtins.toString machine.toh.services.synapse.port})''
        ) machineList
      );
    in
    {
      toh.test.clusters.node = {
        amount = 3;
        module = server;
      };

      toh.test.commands.suffix = ''
        nodes = [ ${nodes} ]

        def holders():
          return [
            node for node in nodes
            if node[0].execute("systemctl is-active matrix-synapse.service")[0] == 0
          ]

        def healthy(machine, ip, port):
          return machine.execute(f"curl -sf http://{ip}:{port}/health")[0] == 0

        def wait_for_holder(excluded):
          def moved(last_try):
            active = holders()
            if last_try:
              assert len(active) == 1, f"{len(active)} nodes run the main process"
            return len(active) == 1 and active[0][0] is not excluded and healthy(*active[0])

          retry(moved, timeout_seconds=300)
          return holders()[0][0]

        # NOTE: the grep calls do not use -q, because it quits at the first
        # match and the test driver runs pipes with pipefail, so the writer
        # would fail on the closed pipe
        def uses_redis(machine):
          machine.wait_until_succeeds(
            "journalctl -u matrix-synapse.service | grep 'Connected to redis' > /dev/null",
            timeout=120,
          )

        # NOTE: the answer has to come from Synapse and not from the proxy,
        # and only Synapse sets a server header like this
        def replication_through_proxy(machine):
          machine.wait_until_succeeds(
            "curl -s -D - -o /dev/null"
            " --resolve ${replication.host}:${builtins.toString replication.port}:127.0.0.1"
            " https://${replication.host}:${builtins.toString replication.port}/_synapse/replication/none"
            " | grep -i '^server: synapse' > /dev/null",
            timeout=120,
          )

        def logged(machine, unit, text):
          return machine.execute(
            f"journalctl -u {unit} | grep -F '{text}' > /dev/null"
          )[0] == 0

        # NOTE: every request carries a query of its own, so the access logs
        # tell which process answered it
        def worker_answers(machine, path):
          machine.wait_until_succeeds(
            "curl --silent --fail"
            " --resolve ${chat.host}:${builtins.toString chat.port}:127.0.0.1"
            f" 'https://${chat.host}:${builtins.toString chat.port}{path}'",
            timeout=120,
          )

          def answered(last_try):
            return any(
              logged(node[0], "matrix-synapse-worker.service", path)
              for node in nodes
            )

          retry(answered, timeout_seconds=60)
          assert not any(
            logged(node[0], "matrix-synapse.service", path) for node in nodes
          ), f"the main process answered {path}"

        for node in nodes:
          node[0].wait_until_succeeds(
            "systemctl is-active matrix-synapse-worker.service", timeout=300
          )

        first = wait_for_holder(None)
        uses_redis(first)
        replication_through_proxy(first)
        worker_answers(first, "/_matrix/client/versions?toh=before-failover")

        first.succeed("systemctl stop toh-lease-synapse.service")
        second = wait_for_holder(first)
        assert second is not first, "the main process did not move"
        uses_redis(second)
        replication_through_proxy(second)
        worker_answers(second, "/_matrix/federation/v1/version?toh=after-failover")
      '';
    }
  );
}
