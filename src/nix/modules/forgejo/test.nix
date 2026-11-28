{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-git-forgejo = selfLib.test.contract.implementation {
    capability = "git";
    implementation = "forgejo";
    server = {
      toh.programs.cli.enable = true;
      toh.services.etcd.enable = true;
      toh.services.coredns.enable = true;
      toh.services.envoy.enable = true;
      toh.services.patroni.enable = true;
      toh.services.cephfs.enable = true;
      toh.services.garage.enable = true;
      toh.services.valkey.enable = true;
      toh.services.lldap.enable = true;
      toh.services.maddy.enable = true;
      toh.services.authelia.enable = true;
      toh.services.forgejo.enable = true;
    };
    # NOTE: the repositories are on CephFS and the rest is in Patroni, and
    # Forgejo is only healthy while its cache in Valkey answers
    test =
      { machines, ... }:
      {
        toh.test.contracts.git.redundant = builtins.concatStringsSep " && " [
          selfLib.test.redundant.patroni
          selfLib.test.redundant.cephfs
          selfLib.test.redundant.valkey
        ];
        toh.test.faults.failoverDelay = selfLib.test.failoverDelay.cephfs machines;
      };
  };

  self.lib.test.faultTests.contracts-git-forgejo = {
    toh.test.contracts.git = {
      enable = true;
      implementation.forgejo = { };
    };
  };

  # NOTE: a git app pushes a repository with a workflow over HTTPS, adds an
  # SSH key through the API and clones the repository back over SSH; the
  # workflow runs on the runners
  self.nixosTests.services-forgejo = selfLib.test.makeNixosTest (
    { machineList, ... }:
    let
      first = (builtins.head machineList).toh.meta.machine.name;
    in
    {
      toh.test.tier = 1;
      toh.test.clusters.node = {
        amount = 3;
        module =
          {
            lib,
            config,
            pkgs,
            ...
          }:
          let
            git = config.toh.meta.git;
            user = git.users.tester;
            api = "${git.url}:${builtins.toString git.http.port}/api/v1";
            repository = "${user.name}/check";

            workflow = pkgs.writeText "check.yaml" (
              builtins.toJSON {
                on = [ "push" ];
                jobs.check = {
                  runs-on = "self-hosted";
                  steps = [ { run = "echo works"; } ];
                };
              }
            );

            credentials = pkgs.writeShellApplication {
              name = "forgejo-check-credentials";
              text = ''
                echo "username=${user.name}"
                echo "password=$(cat ${user.password})"
              '';
            };

            check = pkgs.writeShellApplication {
              name = "forgejo-check";
              runtimeInputs = [
                pkgs.git
                pkgs.openssh
                pkgs.curl
                pkgs.jq
              ];
              # NOTE: jq programs use $ for their own variables in single quotes
              excludeShellChecks = [ "SC2016" ];
              text = ''
                export HOME=/root
                export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
                export GIT_SSH_COMMAND="ssh -i /root/key -p ${builtins.toString git.ssh.port} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
                git config --global credential.helper ${lib.getExe credentials}
                git config --global user.name tester
                git config --global user.email tester@${config.toh.meta.email.domain}
                git config --global init.defaultBranch main
                work="$(mktemp -d)"
                cd "$work"

                case "$1" in
                  push)
                    git init --quiet pushed
                    mkdir -p pushed/.forgejo/workflows
                    cp ${workflow} pushed/.forgejo/workflows/check.yaml
                    echo works > pushed/value
                    git -C pushed add .
                    git -C pushed commit --quiet --message works
                    git -C pushed push --quiet ${git.url}:${builtins.toString git.http.port}/${repository}.git main
                    ;;
                  key)
                    rm -f /root/key /root/key.pub
                    ssh-keygen -q -t ed25519 -N "" -f /root/key
                    jq --null-input --rawfile key /root/key.pub '{ title: "check", key: $key }' \
                      | curl --silent --fail --user "${user.name}:$(cat ${user.password})" \
                        "${api}/user/keys" --json @-
                    ;;
                  clone)
                    git clone --quiet ${git.ssh.user}@${git.ssh.host}:${repository}.git cloned
                    cat cloned/value
                    ;;
                  run)
                    curl --silent --fail --user "${user.name}:$(cat ${user.password})" \
                      "${api}/repos/${repository}/actions/tasks" \
                      | jq --raw-output '.workflow_runs[0].status'
                    ;;
                esac
              '';
            };
          in
          {
            toh.services.etcd.enable = true;
            toh.services.coredns.enable = true;
            toh.services.envoy.enable = true;
            toh.services.patroni.enable = true;
            toh.services.cephfs.enable = true;
            toh.services.garage.enable = true;
            toh.services.valkey.enable = true;
            toh.services.lldap.enable = true;
            toh.services.maddy.enable = true;
            toh.services.authelia.enable = true;
            toh.services.forgejo.enable = true;
            toh.services.forgejo.runner.enable = true;

            toh.meta.git.apps.tester = { };
            users.groups.tester = { };
            users.users.tester = {
              isSystemUser = true;
              group = "tester";
            };

            environment.systemPackages = [ check ];
          };
      };

      toh.test.commands.perNodeInCluster.node = [
        ''command_node.wait_until_succeeds("systemctl is-active toh-git-online.target", timeout=300)''
      ];

      toh.test.commands.suffix = ''
        ${first}.wait_until_succeeds("forgejo-check push", timeout=300)
        ${first}.wait_until_succeeds("forgejo-check key", timeout=60)
        output = ${first}.wait_until_succeeds("forgejo-check clone", timeout=60)
        assert output.strip() == "works", output

        status = ${first}.wait_until_succeeds(
          "forgejo-check run | grep -x -E 'success|failure'", timeout=300
        )
        assert status.strip() == "success", status
      '';
    }
  );
}
