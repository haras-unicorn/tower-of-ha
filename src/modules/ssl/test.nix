{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-ssl = pkgs.tohPackages.testers.runToHTest {
        name = "ssl";
        nodes.machine = {
          toh.ssl.installCa = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("test -d /etc/ssl/certs")
          machine.succeed("test -n \"$(ls -A /etc/ssl/certs/)\"")
        '';
      };
    };
}
