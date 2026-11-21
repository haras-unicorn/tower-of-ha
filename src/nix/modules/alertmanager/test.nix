{ selfLib, ... }:

let
  base = {
    toh.services.etcd.enable = true;
    toh.services.coredns.enable = true;
    toh.services.envoy.enable = true;
    toh.services.prometheus.enable = true;
    toh.services.alertmanager.enable = true;
  };
in
{
  self.lib.test.testModules.contracts-alerts-alertmanager = selfLib.test.contract.implementation {
    capability = "alerts";
    implementation = "alertmanager";
    server = {
      imports = [ base ];
      toh.services.alertmanager.matrix.enable = false;
    };
  };

  self.nixosTests.contracts-alerts-alertmanager = selfLib.test.makeNixosTest {
    toh.test.contracts.alerts = {
      enable = true;
      implementation.alertmanager = { };
    };
  };

  # NOTE: the test reads the room as the user of the bridge, which is in the
  # room already; it logs in once and retries only the reads, because a
  # retried login counts against the login rate limit of Synapse
  self.nixosTests.services-alertmanager-matrix = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      first = builtins.head machineList;
      alert = "TohTest";
    in
    {
      toh.test.clusters.node = {
        amount = 3;
        module =
          { config, pkgs, ... }:
          let
            chat = config.toh.meta.chat;
            user = chat.users.alerts;
          in
          {
            imports = [ base ];

            toh.services.patroni.enable = true;
            toh.services.cephfs.enable = true;
            toh.services.valkey.enable = true;
            toh.services.synapse.enable = true;

            toh.meta.metrics.alerts.${alert} = {
              expression = "vector(1)";
              for = "0s";
              summary = "The test always fires this";
            };

            environment.systemPackages = [
              (pkgs.writeShellApplication {
                name = "alerts-chat";
                runtimeInputs = [
                  pkgs.curl
                  pkgs.jq
                ];
                # NOTE: jq programs use $ for their own variables in single quotes
                excludeShellChecks = [ "SC2016" ];
                text = ''
                  api=${chat.url}/_matrix/client/v3

                  case "$1" in
                    login)
                      jq --null-input --rawfile password ${user.password} '{
                        type: "m.login.password",
                        identifier: { type: "m.id.user", user: "${user.name}" },
                        password: ($password | rtrimstr("\n"))
                      }' \
                        | curl --silent --fail "$api/login" --json @- \
                        | jq --raw-output '"Authorization: Bearer " + .access_token' \
                        > /root/authorization
                      ;;
                    read)
                      alias="$(jq --null-input --raw-output --arg value '${user.room}' '$value | @uri')"
                      room="$(curl --silent --fail --header @/root/authorization \
                        "$api/directory/room/$alias" | jq --raw-output '.room_id | @uri')"
                      curl --silent --fail --header @/root/authorization \
                        "$api/rooms/$room/messages?dir=b&limit=20" \
                        | jq --raw-output \
                          '.chunk[] | select(.type == "m.room.message") | .content | .body, .formatted_body'
                      ;;
                  esac
                '';
              })
            ];
          };
      };

      # NOTE: every bridge logs in as the same user until it runs, so the
      # test logs in only after all of them run
      toh.test.commands.perNodeInCluster.node = [
        ''command_node.wait_until_succeeds("systemctl is-active alertmanager-matrix.service", timeout=300)''
      ];

      toh.test.commands.suffix = ''
        ${first.toh.meta.machine.name}.wait_until_succeeds("alerts-chat login", timeout=60)
        ${first.toh.meta.machine.name}.wait_until_succeeds(
          "alerts-chat read | grep -F ${alert} > /dev/null", timeout=300
        )
      '';
    }
  );
}
