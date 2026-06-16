{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-pki = pkgs.tohPackages.testers.runToHTest {
        name = "pki";
        nodes.machine = {
          toh.pki.installCa = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("test -d /etc/ssl/certs")
          machine.succeed("test -n \"$(ls -A /etc/ssl/certs/)\"")
        '';
      };
    };
}
