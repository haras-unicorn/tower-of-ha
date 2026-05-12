{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-networkmanager = pkgs.tohPackages.testers.runToHTest {
        name = "services-networkmanager";
        nodes.machine = {
          toh.services.networkmanager.enable = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("systemctl is-enabled nftables.service")
          machine.succeed("systemctl is-enabled NetworkManager.service")
        '';
      };
    };
}
