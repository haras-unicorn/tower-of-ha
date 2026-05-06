{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-resolved = pkgs.tohPackages.testers.runToHTest {
        name = "services-resolved";

        toh.test.dns.enable = true;
        toh.test.dns.zones = {
          "test.toh" = {
            "localhost.test.toh" = "127.0.0.1";
          };
        };

        nodes.machine = {
          toh.services.resolved.enable = true;
        };

        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.succeed("systemctl is-enabled systemd-resolved.service")
            machine.succeed("grep 'DNS=${nodes.dns.toh.meta.network.ip}' /etc/systemd/resolved.conf")
            machine.succeed("grep 'DNSSEC=false' /etc/systemd/resolved.conf")
            machine.succeed("grep 'DNSOverTLS=false' /etc/systemd/resolved.conf")
            machine.succeed("grep 'LLMNR=false' /etc/systemd/resolved.conf")
            machine.succeed("resolvectl query localhost.test.toh | grep -q '127.0.0.1'")
            machine.succeed("dig @${nodes.dns.toh.meta.network.ip} localhost.test.toh | grep -q '127.0.0.1'")
            machine.succeed("getent hosts localhost.test.toh | grep -q '127.0.0.1'")
          '';
      };
    };
}
