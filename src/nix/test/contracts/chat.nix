{ selfLib, ... }:

# NOTE: a second client, the reader, logs in on its own and reads what the
# client wrote, so the message has to be in the room and not only in the
# memory of one session; the password and the token never go on a command
# line, curl reads the login from stdin and the header from a file

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

      clientMeta = machines.client.toh.meta;

      client =
        { config, pkgs, ... }:
        let
          chat = config.toh.meta.chat;
          user = chat.users.${app};

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

              jq --null-input --rawfile password ${user.password} '{
                type: "m.login.password",
                identifier: { type: "m.id.user", user: "${user.name}" },
                password: ($password | rtrimstr("\n"))
              }' \
                | curl --silent --fail "$api/login" --json @- \
                | jq --raw-output '"Authorization: Bearer " + .access_token' \
                > authorization

              room="$(curl --silent --fail --header @authorization \
                "$api/directory/room/$(encode '${user.room}')" \
                | jq --raw-output .room_id)"

              case "$1" in
                write)
                  jq --null-input --arg body ${value} '{ msgtype: "m.text", body: $body }' \
                    | curl --silent --fail --request PUT --header @authorization --json @- \
                      "$api/rooms/$(encode "$room")/send/m.room.message/$(date +%s%N)" \
                    > /dev/null
                  ;;
                read)
                  curl --silent --fail --header @authorization \
                    "$api/rooms/$(encode "$room")/messages?dir=b&limit=10" \
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
              client.wait_until_succeeds("contract-chat write", timeout=300)
              reader.wait_until_succeeds("contract-chat read | grep -qx ${value}", timeout=30)
            '';
          }
        ]
      );
    };
}
