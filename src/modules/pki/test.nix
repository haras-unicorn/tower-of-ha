{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-pki = pkgs.tohPackages.testers.runToHTest {
        name = "pki";
        nodes.machine = {
          toh.pki.enable = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("test -d /etc/ssl/certs")
          machine.succeed("test -n \"$(ls -A /etc/ssl/certs/)\"")
          machine.log("OpenSSL module configuration verified successfully")
        '';
      };
    };
}
