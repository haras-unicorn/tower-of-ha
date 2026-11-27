{ selfLib, ... }:

{
  self.nixosTests.services-networkmanager = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    containers.machine = {
      toh.services.networkmanager.enable = true;
    };
    toh.test.commands.suffix = ''
      machine.succeed("systemctl is-enabled nftables.service")
      machine.succeed("systemctl is-enabled NetworkManager.service")
    '';
  };
}
