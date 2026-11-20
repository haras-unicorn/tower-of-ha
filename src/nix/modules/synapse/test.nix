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

  # NOTE: a user of the cluster and a user of a server outside it share a
  # room on the outside server, and each reads what the other wrote, so
  # events go both ways: the invite and the messages of the outside user come
  # in, the join and the messages of the cluster user go out
  self.nixosTests.services-synapse-federation = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      nodes = builtins.filter (
        machine: builtins.substring 0 4 machine.toh.meta.machine.name == "node"
      ) machineList;
      first = builtins.head nodes;

      chat = first.toh.meta.chat;
      domain = "matrix.test";

      subnetRange = subnet: "${subnet.ip}/${builtins.toString subnet.bits}";
      testRange = subnetRange first.toh.meta.network.subnet;
    in
    {
      toh.test.matrix = {
        enable = true;
        inherit domain;
        allowedIpRanges = [ testRange ];
      };

      # NOTE: the outside server finds the cluster at the proxy of one node,
      # which forwards to the main process wherever it runs
      toh.test.dns.zones = selfLib.dns.routeToIp [ chat.host ] first.toh.meta.network.ip;

      defaults =
        { pkgs, ... }:
        {
          environment.systemPackages = [
            (pkgs.writeShellApplication {
              name = "federation-login";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
              ];
              # NOTE: jq programs use $ for their own variables in single quotes
              excludeShellChecks = [ "SC2016" ];
              text = ''
                jq --null-input --arg user "$2" --rawfile password "$3" '{
                  type: "m.login.password",
                  identifier: { type: "m.id.user", user: $user },
                  password: ($password | rtrimstr("\n"))
                }' \
                  | curl --silent --fail "$1/_matrix/client/v3/login" --json @- \
                  | jq --raw-output '"Authorization: Bearer " + .access_token' \
                  > /root/authorization
              '';
            })
          ];
        };

      toh.test.clusters.node = {
        amount = 3;
        module =
          { config, ... }:
          {
            imports = [ server ];
            toh.services.synapse.federation.allowedIpRanges = [
              (subnetRange config.toh.meta.network.subnet)
            ];
            toh.meta.chat.apps.federation = {
              user = "root";
              group = "root";
            };
          };
      };

      toh.test.commands.suffix = ''
        import json
        import urllib.parse

        ours = "${chat.url}"
        theirs = "https://${domain}:8448"
        our_user = "@${chat.users.federation.name}:${chat.serverName}"
        nodes = [ ${
          builtins.concatStringsSep ", " (builtins.map (node: node.toh.meta.machine.name) nodes)
        } ]

        def call(machine, method, url, body=None):
          command = f"curl --silent --fail --request {method} --header @/root/authorization"
          if body is not None:
            command += f" --json '{json.dumps(body)}'"
          status, output = machine.execute(f"{command} '{url}'")
          return json.loads(output) if status == 0 else None

        def until(machine, method, url, body=None, check=lambda _: True):
          found = []

          def done(last_try):
            result = call(machine, method, url, body)
            if result is not None and check(result):
              found.append(result)
            return found != []

          retry(done, timeout_seconds=180)
          return found[0]

        def reads(machine, base, room, text):
          def has_text(result):
            return text in [
              event["content"].get("body")
              for event in result["chunk"]
              if event["type"] == "m.room.message"
            ]

          until(
            machine,
            "GET",
            f"{base}/_matrix/client/v3/rooms/{room}/messages?dir=b&limit=10",
            check=has_text,
          )

        def send(machine, base, room, text):
          until(
            machine,
            "PUT",
            f"{base}/_matrix/client/v3/rooms/{room}/send/m.room.message/{text}",
            { "msgtype": "m.text", "body": text },
          )

        # NOTE: users and rooms of the apps are made after the main process
        # is up, and a login before that fails and counts against the login
        # rate limit; the workers take the federation requests, and a server
        # whose requests fail backs off from the cluster for minutes
        def apps_made(last_try):
          return any(
            node.execute("systemctl is-active synapse-apps.service")[0] == 0
            for node in nodes
          )

        retry(apps_made, timeout_seconds=300)
        for node in nodes:
          node.wait_until_succeeds(
            "systemctl is-active matrix-synapse-worker.service", timeout=300
          )
        matrix.wait_until_succeeds(
          "curl --silent --fail ${chat.url}/_matrix/federation/v1/version",
          timeout=60,
        )

        well_known = json.loads(matrix.wait_until_succeeds(
          "curl --silent --fail ${chat.url}/.well-known/matrix/server",
          timeout=60,
        ))
        assert well_known["m.server"] == "${chat.host}:${builtins.toString chat.port}", well_known

        ${first.toh.meta.machine.name}.wait_until_succeeds(
          "federation-login ${chat.url} ${chat.users.federation.name} ${chat.users.federation.password}",
          timeout=60,
        )

        matrix.succeed("matrix-register-user outside outside-password")
        matrix.succeed("printf outside-password > /root/password")
        matrix.succeed("federation-login https://${domain}:8448 outside /root/password")

        room_id = until(
          matrix, "POST", f"{theirs}/_matrix/client/v3/createRoom", { "preset": "private_chat" }
        )["room_id"]
        room = urllib.parse.quote(room_id, safe="")

        until(
          matrix, "POST", f"{theirs}/_matrix/client/v3/rooms/{room}/invite", { "user_id": our_user }
        )
        until(
          ${first.toh.meta.machine.name},
          "POST",
          f"{ours}/_matrix/client/v3/join/{room}?server_name=${domain}",
          {},
        )

        send(${first.toh.meta.machine.name}, ours, room, "from-the-cluster")
        reads(matrix, theirs, room, "from-the-cluster")

        send(matrix, theirs, room, "from-outside")
        reads(${first.toh.meta.machine.name}, ours, room, "from-outside")
      '';
    }
  );
}
