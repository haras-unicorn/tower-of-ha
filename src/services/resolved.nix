{ self, ... }:

# TODO: dnssec and dnsovertls

{
  flake.nixosModules.services-resolved =
    {
      lib,
      config,
      ...
    }:
    {
      config = {
        networking.networkmanager.dns = "systemd-resolved";
        networking.nameservers = lib.mkBefore [
          # Cloudflare
          "1.1.1.1"
          "1.0.0.1"
          # Google
          "8.8.8.8"
          "8.8.4.4"
        ];

        services.resolved.enable = true;
        services.resolved.fallbackDns = [ ];
        services.resolved.dnssec = "false";
        services.resolved.dnsovertls = "false";
        services.resolved.llmnr = "false";
      };
    };

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
          imports = [
            self.nixosModules.services-resolved
          ];
        };
        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.succeed("systemctl is-enabled systemd-resolved.service")
            machine.succeed("grep 'DNS=${nodes.dns.toh.host.ip}' /etc/systemd/resolved.conf")
            machine.succeed("grep 'DNSSEC=false' /etc/systemd/resolved.conf")
            machine.succeed("grep 'DNSOverTLS=false' /etc/systemd/resolved.conf")
            machine.succeed("grep 'LLMNR=false' /etc/systemd/resolved.conf")
            machine.succeed("resolvectl query localhost.test.toh | grep -q '127.0.0.1'")
            machine.succeed("dig @${nodes.dns.toh.host.ip} localhost.test.toh | grep -q '127.0.0.1'")
            machine.succeed("getent hosts localhost.test.toh | grep -q '127.0.0.1'")
          '';
      };
    };
}
