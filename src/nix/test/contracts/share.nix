{ selfLib, ... }:

# NOTE: a second client, the reader, reads what the client wrote, so the share
# has to be shared: a directory on one machine cannot pass; the password goes
# to smbclient in the environment and not on the command line

{
  self.lib.test.testModules.contracts-share =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.share;

      kind = config.toh.test.kind;

      app = selfLib.test.contract.app;
      value = "works";

      clientMeta = machines.client.toh.meta;

      client =
        { config, pkgs, ... }:
        let
          share = config.toh.meta.share;
          entry = share.shares.${app};

          run = pkgs.writeShellApplication {
            name = "contract-share-run";
            runtimeInputs = [
              pkgs.samba
              pkgs.coreutils
            ];
            text = ''
              PASSWD="$(cat ${entry.password})"
              export PASSWD
              HOME="$(mktemp -d)"
              export HOME
              cd "$HOME"

              smb() {
                smbclient "//${share.host}/${entry.name}" \
                  -p ${builtins.toString share.port} -U ${entry.user} -c "$1"
              }

              case "$1" in
                write)
                  echo ${value} > value
                  smb 'put value'
                  ;;
                read)
                  smb 'get value' >/dev/null
                  cat value
                  ;;
              esac
            '';
          };

          contract = pkgs.writeShellApplication {
            name = "contract-share";
            runtimeInputs = [ pkgs.util-linux ];
            text = ''
              exec setpriv --reuid=${app} --regid=${app} --init-groups \
                ${lib.getExe run} "$@"
            '';
          };
        in
        {
          toh.meta.share.apps.${app} = { };

          environment.systemPackages = [ contract ];
        };
    in
    {
      options.toh.test.contracts.share = selfLib.test.contract.options "share" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg kind client;
            names.${clientMeta.share.host} = clientMeta.relays;
          })
          (selfLib.test.ofKind kind {
            reader = selfLib.test.contract.clientModule client;
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-share write", timeout=300)
              reader.wait_until_succeeds("contract-share read | grep -qx ${value}", timeout=30)
            '';
          }
        ]
      );
    };
}
