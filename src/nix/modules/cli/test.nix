{ selfLib, ... }:

{
  self.nixosTests.services-cli = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    containers.machine = {
      toh.programs.cli.enable = true;
    };
    toh.test.commands.suffix = ''
      machine.succeed("toh")
    '';
  };
}
