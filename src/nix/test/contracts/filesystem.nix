{ selfLib, ... }:

# NOTE: a second client, the reader, mounts the same directory as the client,
# so what it reads back only got there through the shared filesystem; a
# local filesystem on one machine cannot pass

{
  self.lib.test.testModules.contracts-filesystem =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.filesystem;

      kind = config.toh.test.kind;

      app = selfLib.test.contract.app;
      directory = "/${app}";
      mountPath = "/mnt/${app}";
      value = "works";

      # NOTE: a write counts once sync says the file is on the servers
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "filesystem";
        write = ''lambda value: f"contract-filesystem write-value {value}"'';
        holds = ''lambda value: f"contract-filesystem read-value {value} | grep -x {value}"'';
        reader = "reader";
      };

      client =
        { pkgs, ... }:
        let
          contract = pkgs.writeShellApplication {
            name = "contract-filesystem";
            runtimeInputs = [ pkgs.util-linux ];
            text = ''
              as_app() {
                setpriv --reuid=${app} --regid=${app} --init-groups "$@"
              }

              case "$1" in
                mounted)
                  mountpoint -q ${mountPath}
                  ;;
                write)
                  as_app tee ${mountPath}/value <<<"${value}" >/dev/null
                  ;;
                read)
                  as_app cat ${mountPath}/value
                  ;;
                write-value)
                  as_app tee "${mountPath}/$2" <<<"$2" >/dev/null
                  as_app sync "${mountPath}/$2"
                  ;;
                read-value)
                  as_app cat "${mountPath}/$2"
                  ;;
              esac
            '';
          };
        in
        {
          toh.meta.filesystem.mounts.${mountPath} = {
            inherit directory;
            user = app;
            group = app;
          };

          environment.systemPackages = [ contract ];
        };
    in
    {
      options.toh.test.contracts.filesystem = selfLib.test.contract.options "filesystem" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg kind client;
            names = { };
          })
          (selfLib.test.ofKind kind {
            reader = selfLib.test.contract.clientModule client;
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-filesystem mounted", timeout=300)
              reader.wait_until_succeeds("contract-filesystem mounted", timeout=300)
              client.succeed("contract-filesystem write")
              reader.wait_until_succeeds("contract-filesystem read | grep -qx ${value}", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
