{ selfLib, inputs, ... }:

let
  # NOTE: the dash is on purpose, systemd names the mount unit of a path
  # with a dash differently from one without
  mountPath = "/mnt/ceph-mount";

  healthCommands = allowedChecks: [
    ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-online.target", timeout=300)''
    ''
      import json
      allowed = json.loads('${builtins.toJSON ([ "MON_CLOCK_SKEW" ] ++ allowedChecks)}')

      def healthy(last_try):
        status = json.loads(command_node.succeed("ceph -s --format json"))
        unexpected = [
          check for check in status["health"].get("checks", {})
          if not any(check.startswith(prefix) for prefix in allowed)
        ]
        if last_try:
          assert not unexpected, f"CephFS is suffering from something other than {allowed}: '{status}'"
        return not unexpected

      retry(healthy, timeout_seconds=60)
    ''
  ];

  mountCommands =
    allowedChecks:
    healthCommands allowedChecks
    ++ [
      (
        node:
        let
          name = node.toh.meta.machine.name;
        in
        ''
          command_node.succeed("echo 'Hello from ${name}!' > ${mountPath}/hello-world-${name}")
        ''
      )
      (
        { node, machineList, ... }:
        let
          others = builtins.filter (
            other: other.toh.meta.machine.name != node.toh.meta.machine.name
          ) machineList;
        in
        builtins.concatStringsSep "\n" (
          builtins.map (
            other:
            let
              name = other.toh.meta.machine.name;
            in
            ''command_node.succeed("cat ${mountPath}/hello-world-${name} | grep -q 'Hello from ${name}!'")''
          ) others
        )
      )
    ];
in
{
  self.lib.test.testModules.contracts-filesystem-cephfs = selfLib.test.contract.implementation {
    capability = "filesystem";
    implementation = "cephfs";
    server = {
      toh.services.cephfs.enable = true;
    };
    test =
      { machines, ... }:
      {
        toh.test.contracts.filesystem.redundant = selfLib.test.redundant.cephfs;
        toh.test.faults.failoverDelay = selfLib.test.failoverDelay.cephfs machines;
      };
  };

  self.nixosTests.contracts-filesystem-cephfs = selfLib.test.makeNixosTest {
    toh.test.contracts.filesystem = {
      enable = true;
      implementation.cephfs = { };
    };
  };

  self.nixosTests.services-cephfs = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.cephfs.enable = true;
      };
    };

    toh.test.commands.perNodeInCluster.node = healthCommands [ ];
  };

  self.nixosTests.services-cephfs-mount = selfLib.test.makeNixosTest {
    toh.test.clusters.node = {
      amount = 3;
      module = {
        toh.services.cephfs.enable = true;
        toh.meta.filesystem.mounts.${mountPath} = { };
      };
    };

    toh.test.commands.perNodeInCluster.node = mountCommands [ ];
  };

  # NOTE: kernels before 7.0 refuse the 32 byte keys newer ceph makes, and
  # the test vms run an older kernel, so this test makes cryl generate the
  # old 16 byte keys; `dev test` skips it until the kernel catches up
  self.nixosTests.services-cephfs-kernel-mount = selfLib.test.makeNixosTest (
    { lib, pkgs, ... }:
    {
      # NOTE: ceph OSDs need disks and the mounts a kernel module
      toh.test.kind = "vm";
      passthru.skipped = true;

      # NOTE: cryl has no option for the key type, so its ceph-authtool
      # is swapped for one that asks for aes; the cryl wrapper puts its
      # own tools first in PATH, so this wraps the unwrapped cryl with the
      # same tools behind the swapped one
      cryl.package =
        let
          crylPackages = inputs.cryl.packages.${pkgs.stdenv.hostPlatform.system};

          crylTools = builtins.map (name: crylPackages.${name}) (
            builtins.filter (lib.hasPrefix "build-input") (builtins.attrNames crylPackages)
          );

          aesCephAuthtool =
            pkgs.runCommand "ceph-authtool-aes"
              {
                nativeBuildInputs = [ pkgs.makeWrapper ];
              }
              ''
                makeWrapper ${pkgs.ceph-client}/bin/ceph-authtool \
                  $out/bin/ceph-authtool \
                  --add-flags "--key-type aes"
              '';
        in
        pkgs.runCommand "cryl-aes-ceph-keys"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta.mainProgram = "cryl";
          }
          ''
            makeWrapper ${crylPackages.unwrapped}/bin/cryl $out/bin/cryl \
              --prefix PATH : ${lib.makeBinPath ([ aesCephAuthtool ] ++ crylTools)}
          '';

      toh.test.clusters.node = {
        amount = 3;
        module = {
          toh.services.cephfs.enable = true;
          toh.services.cephfs.mountDriver = "kernel";
          toh.services.cephfs.keyType = "aes";
          toh.meta.filesystem.mounts.${mountPath} = { };
        };
      };

      # NOTE: allowing aes keys is what the insecure key checks warn about
      toh.test.commands.perNodeInCluster.node = mountCommands [ "AUTH_INSECURE" ];
    }
  );
}
