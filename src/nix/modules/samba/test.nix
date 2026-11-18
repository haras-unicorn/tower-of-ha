{ lib, selfLib, ... }:

{
  self.nixosTests.services-samba =
    let
      user = "test";
      password = "test";
      mntShare = "mnt-test";
      mntShareLocation = "/mnt/test";
      share = "share";

      makeNodeAttrs =
        node:
        let
          proxyAttrs = selfLib.services.endpoint.toAttrs node.toh.meta.proxies.samba.endpoint;

          makeProxyArgs =
            share:
            "//${proxyAttrs.host}"
            + lib.optionalString (share != null) "/${share}"
            + " -p ${builtins.toString proxyAttrs.port}"
            + " -U ${user}%${password}";
        in
        {
          name = node.toh.meta.machine.name;
          proxyArgs = makeProxyArgs null;
          mntArgs = makeProxyArgs mntShare;
        };
    in
    selfLib.test.makeNixosTest {
      toh.test.clusters.node = {
        amount = 2;
        module = {
          toh.services.cephfs.enable = true;
          toh.services.etcd.enable = true;
          toh.services.coredns.enable = true;
          toh.services.haproxy.enable = true;
          toh.services.samba.enable = true;
          toh.meta.filesystem.mounts.${mntShareLocation} = {
            user = user;
            group = user;
            share = {
              name = mntShare;
            };
          };
        };
      };

      toh.test.commands.perNodeInCluster.node = [
        ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-online.target", timeout=300)''
        (
          node:
          let
            inherit (makeNodeAttrs node) name proxyArgs mntArgs;
          in
          ''
            command_node.succeed("""
              (echo ${password}; echo ${password}) | smbpasswd -a ${user} -s
            """)
            command_node.wait_until_succeeds("""
              smbclient -L ${proxyArgs}
            """, timeout=120)
            command_node.succeed("""
              echo "Hello from ${name}!" \
                | smbclient ${mntArgs} -c 'put - hello-world-${name}' \
                && smbclient ${mntArgs} -c 'get hello-world-${name}' \
                && grep ${name} hello-world-${name}
            """)
          ''
        )
        (
          { machineList, ... }:
          builtins.map (
            node:
            let
              inherit (makeNodeAttrs node) name;
            in
            ''
              command_node.succeed("grep ${name} ${mntShareLocation}/hello-world-${name}")
            ''
          ) machineList
        )
        (
          node:
          let
            inherit (makeNodeAttrs node) proxyArgs;
          in
          ''
            command_node.succeed("""
              if ! smbclient -L ${proxyArgs} 2>&1 | grep -q ${share}; then
                mkdir -p /var/lib/samba/userdata/${share}
                net usershare add ${share} /var/lib/samba/userdata/${share} test ${user}:F
              fi
            """)
            command_node.succeed("""
              smbclient -L ${proxyArgs} | grep ${share}
            """)
          ''
        )
      ];

      toh.test.commands.suffix =
        { machineList, ... }:
        let
          names = builtins.map (node: node.toh.meta.machine.name) machineList;
          inherit (makeNodeAttrs (builtins.head machineList)) mntArgs;
        in
        ''
          samba_nodes = [${builtins.concatStringsSep ", " names}]

          def samba_leaders():
            return [
              node for node in samba_nodes
              if node.execute("systemctl is-active samba-smbd.service")[0] == 0
            ]

          leaders = samba_leaders()
          assert len(leaders) == 1, f"Expected one smbd, got {len(leaders)}"
          old_leader = leaders[0]
          old_leader.succeed("systemctl stop toh-lease-samba.service")

          def new_leader_took_over(_):
            leaders = samba_leaders()
            return len(leaders) == 1 and leaders[0] != old_leader

          retry(new_leader_took_over, timeout_seconds=60)
          new_leader = samba_leaders()[0]
          new_leader.wait_until_succeeds("""
            smbclient ${mntArgs} -c 'ls'
          """, timeout=120)
        '';
    };
}
