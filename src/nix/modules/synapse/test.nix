{ selfLib, ... }:

let
  server = {
    toh.services.etcd.enable = true;
    toh.services.coredns.enable = true;
    toh.services.haproxy.enable = true;
    toh.services.patroni.enable = true;
    toh.services.cephfs.enable = true;
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

        first = wait_for_holder(None)

        first.succeed("systemctl stop toh-lease-synapse.service")
        second = wait_for_holder(first)
        assert second is not first, "the main process did not move"
      '';
    }
  );
}
