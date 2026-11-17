{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-coredns = pkgs.tohPackages.testers.runToHTest {
        name = "services-coredns";

        toh.test.dns.enable = true;
        toh.test.dns.zones = {
          "test.toh" = {
            "localhost.test.toh" = "127.0.0.1";
          };
        };

        nodes.machine = {
          toh.services.coredns.enable = true;
        };

        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.wait_for_unit("coredns.service")
            machine.succeed("getent hosts localhost.test.toh | grep -q '127.0.0.1'")
            machine.succeed("dig @${nodes.dns.toh.meta.network.ip} localhost.test.toh | grep -q '127.0.0.1'")
          '';
      };
    };
}
