{ selfLib, ... }:

# NOTE: a second client, the reader, logs in on its own and reads what the
# client wrote, so the message has to be in the room and not only in the
# memory of one session; the password and the token never go on a command
# line, curl reads the login from stdin and the header from a file

# NOTE: each client logs in once and keeps the token, and only the steps
# after the login are retried, because a retried login counts against the
# login rate limit of the server, which a retry loop never gets under again

{
  self.lib.test.testModules.contracts-chat =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.chat;

      kind = config.toh.test.kind;

      app = selfLib.test.contract.app;
      value = "works";

      # NOTE: the first message and two of every failover round, with room
      readLimit = 50;

      clientMeta = machines.client.toh.meta;

      # NOTE: a message counts once the server answered its send, and the
      # reader finds it with its own login
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "chat";
        write = ''lambda value: f"contract-chat write {value}"'';
        holds = ''lambda value: f"contract-chat read | grep -x {value}"'';
        reader = "reader";
      };

      client =
        { config, pkgs, ... }:
        let
          chat = config.toh.meta.chat;
          user = chat.users.${app};

          stateDirectory = "/var/lib/contract-chat";
          authorization = "${stateDirectory}/authorization";

          run = pkgs.writeShellApplication {
            name = "contract-chat-run";
            # NOTE: jq programs use $ for their own variables in single quotes
            excludeShellChecks = [ "SC2016" ];
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
            ];
            text = ''
              HOME="$(mktemp -d)"
              export HOME
              cd "$HOME"

              api=${chat.url}/_matrix/client/v3

              encode() {
                jq --null-input --raw-output --arg value "$1" '$value | @uri'
              }

              room() {
                curl --silent --fail --header @${authorization} \
                  "$api/directory/room/$(encode '${user.room}')" \
                  | jq --raw-output .room_id
              }

              case "$1" in
                login)
                  jq --null-input --rawfile password ${user.password} '{
                    type: "m.login.password",
                    identifier: { type: "m.id.user", user: "${user.name}" },
                    password: ($password | rtrimstr("\n"))
                  }' \
                    | curl --silent --fail "$api/login" --json @- \
                    | jq --raw-output '"Authorization: Bearer " + .access_token' \
                    > ${authorization}
                  ;;
                write)
                  room_id="$(room)"
                  jq --null-input --arg body "''${2:-${value}}" '{ msgtype: "m.text", body: $body }' \
                    | curl --silent --fail --request PUT --header @${authorization} --json @- \
                      "$api/rooms/$(encode "$room_id")/send/m.room.message/$(date +%s%N)" \
                    > /dev/null
                  ;;
                read)
                  room_id="$(room)"
                  curl --silent --fail --header @${authorization} \
                    "$api/rooms/$(encode "$room_id")/messages?dir=b&limit=${builtins.toString readLimit}" \
                    | jq --raw-output \
                      '.chunk[] | select(.type == "m.room.message") | .content.body'
                  ;;
              esac
            '';
          };

          contract = pkgs.writeShellApplication {
            name = "contract-chat";
            runtimeInputs = [ pkgs.util-linux ];
            text = ''
              exec setpriv --reuid=${app} --regid=${app} --init-groups \
                ${lib.getExe run} "$@"
            '';
          };
        in
        {
          toh.meta.chat.apps.${app} = { };

          toh.pki.installCa = true;

          systemd.tmpfiles.rules = [ "d ${stateDirectory} 0700 ${app} ${app} -" ];

          environment.systemPackages = [ contract ];
        };
    in
    {
      options.toh.test.contracts.chat = selfLib.test.contract.options "chat" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg kind client;
            names.${clientMeta.chat.host} = clientMeta.relays;
          })
          (selfLib.test.ofKind kind {
            reader = selfLib.test.contract.clientModule client;
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-chat login", timeout=300)
              client.wait_until_succeeds("contract-chat write", timeout=300)
              reader.wait_until_succeeds("contract-chat login", timeout=60)
              reader.wait_until_succeeds("contract-chat read | grep -x ${value} > /dev/null", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
