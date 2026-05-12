{
  perSystem =
    { pkgs, lib, ... }:
    {
      checks.test-services-haproxy = pkgs.tohPackages.testers.runToHTest (
        { nodea, ... }:
        let
          amount = 3;

          ips = lib.concatMapStringsSep ", " (node: ''"${node.toh.meta.network.ip}"'') nodea;
        in
        {
          name = "services-haproxy";

          toh.test.clusters.node = {
            inherit amount;
            module =
              { config, ... }:
              {
                toh.ssl.installCa = true;

                toh.services.coredns.enable = true;

                toh.services.haproxy.enable = true;

                toh.test.http = {
                  enable = true;
                  tls = false;
                  domains = [ "http.${config.toh.meta.domains.service}" ];
                  handler = ''response = "${config.toh.meta.network.ip}"'';
                };

                toh.meta.services = [
                  {
                    name = "http";
                    port = 80;
                    health = "http:///health";
                  }
                ];
              };
          };

          toh.test.commands.prefix = ''
            node_ips = set([ ${ips} ])
          '';

          toh.test.commands.perNodeInCluster.node = [
            ''command_node.wait_for_unit("coredns.service")''
            ''command_node.wait_for_unit("haproxy.service")''
            ''command_node.wait_for_unit("http.service")''
            (node: ''
              ips = set([
                command_node.succeed(
                  "curl -s https://http.${node.toh.meta.domains.service}"
                ).strip()
                for _ in range(${builtins.toString (amount * 3)})
              ])
              assert ips == node_ips, f"{ips} != {node_ips}"
            '')
          ];
        }
      );
    };
}
