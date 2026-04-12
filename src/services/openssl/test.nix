{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-openssl = pkgs.tohPackages.testers.runToHTest {
        name = "services-openssl";
        nodes.machine = {
          toh.test.openssl.enable = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("test -d /etc/ssl/certs")
          machine.succeed("test -n \"$(ls -A /etc/ssl/certs/)\"")
          machine.log("OpenSSL module configuration verified successfully")
        '';
      };
    };
}
