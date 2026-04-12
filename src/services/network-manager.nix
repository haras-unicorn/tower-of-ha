{ self, ... }:

{
  flake.nixosModules.services-network-manager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      config = {
        networking.nftables.enable = true;
        networking.firewall.enable = true;

        networking.networkmanager.enable = true;
        systemd.network.wait-online.enable = false;

        programs.rust-motd.settings = {
          service_status = {
            Network = "systemd-networkd";
          };
        };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-network-manager = pkgs.tohPackages.testers.runToHTest {
        name = "services-network-manager";
        nodes.machine = {
          imports = [
            self.nixosModules.services-network-manager
          ];
        };
        toh.test.commands.suffix = ''
          machine.succeed("systemctl is-enabled nftables.service")
          machine.succeed("systemctl is-enabled NetworkManager.service")
        '';
      };
    };
}
