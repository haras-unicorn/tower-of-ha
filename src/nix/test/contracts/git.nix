{ selfLib, ... }:

# NOTE: the client makes its repository by pushing to it, so the contract
# needs nothing but git; the password goes to git through a credential helper
# and not on the command line

{
  self.lib.test.testModules.contracts-git =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.git;

      app = selfLib.test.contract.app;
      value = "works";

      clientMeta = machines.client.toh.meta;

      # NOTE: every value is a branch of its own, pushed from a new repository
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "git";
        write = ''lambda value: f"contract-git push-value {value}"'';
        holds = ''lambda value: f"contract-git clone-value {value} | grep -x {value}"'';
      };
    in
    {
      options.toh.test.contracts.git = selfLib.test.contract.options "git" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${clientMeta.git.http.host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                git = config.toh.meta.git;
                user = git.users.${app};
                repository = "${git.url}:${builtins.toString git.http.port}/${user.name}/${app}.git";

                credentials = pkgs.writeShellApplication {
                  name = "contract-git-credentials";
                  text = ''
                    echo "username=${user.name}"
                    echo "password=$(cat ${user.password})"
                  '';
                };

                run = pkgs.writeShellApplication {
                  name = "contract-git-run";
                  runtimeInputs = [ pkgs.git ];
                  text = ''
                    HOME="$(mktemp -d)"
                    export HOME
                    export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
                    git config --global credential.helper ${lib.getExe credentials}
                    git config --global user.name ${app}
                    git config --global user.email ${app}@${config.toh.meta.email.domain}
                    git config --global init.defaultBranch main
                    cd "$HOME"

                    case "$1" in
                      push)
                        git init --quiet pushed
                        echo ${value} > pushed/value
                        git -C pushed add value
                        git -C pushed commit --quiet --message ${value}
                        git -C pushed push --quiet ${repository} main
                        ;;
                      clone)
                        git clone --quiet ${repository} cloned
                        cat cloned/value
                        ;;
                      push-value)
                        git init --quiet pushed
                        echo "$2" > pushed/value
                        git -C pushed add value
                        git -C pushed commit --quiet --message "$2"
                        git -C pushed push --quiet ${repository} "main:$2"
                        ;;
                      clone-value)
                        git clone --quiet --branch "$2" ${repository} cloned
                        cat cloned/value
                        ;;
                    esac
                  '';
                };

                contract = pkgs.writeShellApplication {
                  name = "contract-git";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      ${lib.getExe run} "$@"
                  '';
                };
              in
              {
                toh.meta.git.apps.${app} = { };

                toh.pki.installCa = true;

                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-git push", timeout=300)
              client.wait_until_succeeds("contract-git clone | grep -qx ${value}", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
