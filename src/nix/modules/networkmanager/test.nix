{ selfLib, ... }:

{
  self.nixosTests.services-networkmanager = selfLib.test.makeNixosTest {
    containers.machine = {
      toh.services.networkmanager.enable = true;
    };
    toh.test.commands.suffix = ''
      machine.succeed("systemctl is-enabled nftables.service")
      machine.succeed("systemctl is-enabled NetworkManager.service")
    '';
  };
}
