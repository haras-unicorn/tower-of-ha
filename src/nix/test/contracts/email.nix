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
      subject = "contract works";

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

                submission = "smtps://${email.submission.host}:${builtins.toString email.submission.port}";
                imap = "imaps://${email.imap.host}:${builtins.toString email.imap.port}/INBOX";

                message = pkgs.writeText "contract-email-message" ''
                  From: ${inbox.address}
                  To: ${inbox.address}
                  Subject: ${subject}

                  ${subject}
                '';

                curl = pkgs.writeShellApplication {
                  name = "contract-email-curl";
                  runtimeInputs = [ pkgs.curl ];
                  text = ''
                    curl --fail --silent --show-error \
                      --config <(printf 'user = "%s:%s"\n' \
                        "${inbox.address}" "$(cat ${inbox.password})") \
                      "$@"
                  '';
                };

                client = pkgs.writeShellApplication {
                  name = "contract-email";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    run() {
                      setpriv --reuid=${app} --regid=${app} --init-groups \
                        ${lib.getExe curl} "$@"
                    }

                    case "$1" in
                      send)
                        run --url "${submission}" \
                          --mail-from "${inbox.address}" \
                          --mail-rcpt "${inbox.address}" \
                          --upload-file ${message} --crlf
                        ;;
                      find)
                        run --url "${imap}" --request 'SEARCH SUBJECT "${subject}"'
                        ;;
                      send-value)
                        printf 'From: %s\nTo: %s\nSubject: %s\n\n%s\n' \
                          "${inbox.address}" "${inbox.address}" "$2" "$2" |
                          run --url "${submission}" \
                            --mail-from "${inbox.address}" \
                            --mail-rcpt "${inbox.address}" \
                            --upload-file - --crlf
                        ;;
                      find-value)
                        run --url "${imap}" --request "SEARCH SUBJECT \"$2\""
                        ;;
                    esac
                  '';
                };
              in
              {
                toh.meta.email.apps.${app} = { };

                toh.pki.installCa = true;

                environment.systemPackages = [ client ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-email send", timeout=300)
              client.wait_until_succeeds("contract-email find | grep -Eq '^\\* SEARCH [0-9]+'", timeout=60)

              ${failover}
            '';
          }
        ]
      );
    };
}
