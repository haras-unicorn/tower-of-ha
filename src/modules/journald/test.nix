{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-journald = pkgs.tohPackages.testers.runToHTest {
        name = "services-journald";
        nodes.machine = {
          toh.services.journald.enable = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("grep 'SystemMaxUse=750M' /etc/systemd/journald.conf")
          machine.succeed("grep 'SystemMaxFileSize=100M' /etc/systemd/journald.conf")
          machine.succeed("grep 'MaxRetentionSec=1month' /etc/systemd/journald.conf")
        '';
      };
    };
}
