{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-email =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.email;

      app = selfLib.test.contract.app;
      # NOTE: a second inbox of the same user, so the mail of one app to
      # another goes through the server and not around it
      otherApp = "${app}-other";
      subject = "contract works";
      otherSubject = "contract reaches";
      # NOTE: an app that sends as another is refused with 553, the code for a
      # sender the user may not use; a server may say so at MAIL or, like
      # Maddy, hold it back until RCPT, so only the code is checked
      refusedSender = ": 553";

      clientMeta = machines.client.toh.meta;
      email = clientMeta.email;

      # NOTE: a mail counts once the submission says it took it, and every
      # value is the subject of a mail of its own
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "email";
        write = ''lambda value: f"contract-email send-value {value}"'';
        holds = ''lambda value: f"contract-email find-value {value} | grep -E '^[*] SEARCH [0-9]+'"'';
      };
    in
    {
      options.toh.test.contracts.email = selfLib.test.contract.options "email" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names = lib.genAttrs (lib.unique [
              email.submission.host
              email.imap.host
            ]) (_: clientMeta.relays);
            client =
              { config, pkgs, ... }:
              let
                email = config.toh.meta.email;
                inbox = email.emails.${app};
                otherInbox = email.emails.${otherApp};

                submission = "smtps://${email.submission.host}:${builtins.toString email.submission.port}";
                imap = "imaps://${email.imap.host}:${builtins.toString email.imap.port}/INBOX";

                curlAs =
                  name: inbox:
                  pkgs.writeShellApplication {
                    inherit name;
                    runtimeInputs = [ pkgs.curl ];
                    text = ''
                      curl --fail --silent --show-error \
                        --config <(printf 'user = "%s:%s"\n' \
                          "${inbox.address}" "$(cat ${inbox.password})") \
                        "$@"
                    '';
                  };
                curl = curlAs "contract-email-curl" inbox;
                otherCurl = curlAs "contract-email-curl-other" otherInbox;

                client = pkgs.writeShellApplication {
                  name = "contract-email";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    run() {
                      setpriv --reuid=${app} --regid=${app} --init-groups "$@"
                    }

                    # from, to, subject
                    send() {
                      printf 'From: %s\nTo: %s\nSubject: %s\n\n%s\n' \
                        "$1" "$2" "$3" "$3" |
                        run ${lib.getExe curl} --url "${submission}" \
                          --mail-from "$1" \
                          --mail-rcpt "$2" \
                          --upload-file - --crlf
                    }

                    case "$1" in
                      send)
                        send "${inbox.address}" "${inbox.address}" "${subject}"
                        ;;
                      find)
                        run ${lib.getExe curl} --url "${imap}" \
                          --request 'SEARCH SUBJECT "${subject}"'
                        ;;
                      send-other)
                        send "${inbox.address}" "${otherInbox.address}" "${otherSubject}"
                        ;;
                      find-other)
                        run ${lib.getExe otherCurl} --url "${imap}" \
                          --request 'SEARCH SUBJECT "${otherSubject}"'
                        ;;
                      send-forged)
                        send "${otherInbox.address}" "${inbox.address}" "${otherSubject}"
                        ;;
                      send-value)
                        send "${inbox.address}" "${inbox.address}" "$2"
                        ;;
                      find-value)
                        run ${lib.getExe curl} --url "${imap}" \
                          --request "SEARCH SUBJECT \"$2\""
                        ;;
                    esac
                  '';
                };
              in
              {
                toh.meta.email.apps.${app} = { };
                toh.meta.email.apps.${otherApp} = {
                  user = app;
                  group = app;
                };

                toh.pki.installCa = true;

                environment.systemPackages = [ client ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-email send", timeout=300)
              client.wait_until_succeeds("contract-email find | grep -Eq '^\\* SEARCH [0-9]+'", timeout=60)
              client.succeed("contract-email send-other")
              client.wait_until_succeeds("contract-email find-other | grep -Eq '^\\* SEARCH [0-9]+'", timeout=60)
              output = client.succeed("contract-email send-forged 2>&1 || true")
              assert "${refusedSender}" in output, output

              ${failover}
            '';
          }
        ]
      );
    };
}
