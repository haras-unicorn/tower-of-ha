{ selfLib, ... }:

{
  self.nixosTests.pki = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    containers.machine = {
      toh.pki.installCa = true;
    };
    toh.test.commands.suffix = ''
      machine.succeed("test -d /etc/ssl/certs")
      machine.succeed("test -n \"$(ls -A /etc/ssl/certs/)\"")
    '';
  };
}
