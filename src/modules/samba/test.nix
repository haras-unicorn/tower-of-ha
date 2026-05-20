{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.test-services-samba =
        let
          user = "test";
          mntShare = "mnt-test";
          mntShareLocation = "/mnt/test";
          share = "share";
        in
        pkgs.tohPackages.testers.runToHTest

          {
            name = "services-samba";

            toh.test.clusters.node = {
              amount = 2;
              module = {
                toh.services.cephfs.enable = true;
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

            toh.test.commands.perNodeInCluster.node =
              let
                password = "test";

                makeNodeAttrs = node: rec {
                  name = node.toh.meta.machine.name;
                  proxyAttrs = node.toh.lib.services.endpoint.toAttrs node.toh.meta.proxies.samba.endpoint;
                  makeProxyArgs =
                    share:
                    "//${proxyAttrs.host}"
                    + lib.optionalString (share != null) "/${share}"
                    + " -p ${builtins.toString proxyAttrs.port}"
                    + " -U ${user}%${password}";

                  proxyArgs = makeProxyArgs null;
                  mntArgs = makeProxyArgs mntShare;
                  shareArgs = makeProxyArgs share;
                };
              in
              [
                ''command_node.wait_until_succeeds("systemctl is-active toh-filesystem-initialized.target", timeout=300)''
                (
                  node:
                  let
                    inherit (makeNodeAttrs node) name proxyArgs mntArgs;
                  in
                  ''
                    command_node.succeed("""
                      (echo ${password}; echo ${password}) | smbpasswd -a ${user} -s
                    """)
                    command_node.succeed("""
                      smbclient -L ${proxyArgs}
                    """)
                    command_node.succeed("""
                      echo "Hello from ${name}!" \
                        | smbclient ${mntArgs} -c 'put - hello-world-${name}' \
                        && smbclient ${mntArgs} -c 'get hello-world-${name}' \
                        && grep ${name} hello-world-${name}
                    """)
                  ''
                )
                (
                  { nodea, ... }:
                  builtins.map (
                    node:
                    let
                      inherit (makeNodeAttrs node) name;
                    in
                    ''
                      command_node.succeed("grep ${name} ${mntShareLocation}/hello-world-${name}")
                    ''
                  ) nodea
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
          };
    };
}
