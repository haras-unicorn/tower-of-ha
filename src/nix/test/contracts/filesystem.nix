{ selfLib, ... }:

# NOTE: the client mounts the same directory twice, so the file it writes
# through one mount and reads through the other comes from the shared
# filesystem and not from a local cache

{
  self.lib.test.testModules.contracts-filesystem =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.test.contracts.filesystem;

      app = selfLib.test.contract.app;
      directory = "/${app}";
      writeMount = "/mnt/${app}-write";
      readMount = "/mnt/${app}-read";
      value = "works";
    in
    {
      options.toh.test.contracts.filesystem = selfLib.test.contract.options "filesystem" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names = { };
            client =
              { pkgs, ... }:
              let
                mount = {
                  inherit directory;
                  user = app;
                  group = app;
                };

                contract = pkgs.writeShellApplication {
                  name = "contract-filesystem";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    as_app() {
                      setpriv --reuid=${app} --regid=${app} --init-groups "$@"
                    }

                    case "$1" in
                      mounted)
                        mountpoint -q ${writeMount} && mountpoint -q ${readMount}
                        ;;
                      write)
                        as_app tee ${writeMount}/value <<<"${value}" >/dev/null
                        ;;
                      read)
                        as_app cat ${readMount}/value
                        ;;
                    esac
                  '';
                };
              in
              {
                toh.meta.filesystem.mounts = {
                  ${writeMount} = mount;
                  ${readMount} = mount;
                };

                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-filesystem mounted", timeout=300)
              client.succeed("contract-filesystem write")
              client.wait_until_succeeds("contract-filesystem read | grep -qx ${value}", timeout=30)
            '';
          }
        ]
      );
    };
}
