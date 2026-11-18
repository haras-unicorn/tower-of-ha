{ selfLib, ... }:

{
  self.nixosTests.services-cli = selfLib.test.makeNixosTest {
    containers.machine = {
      toh.programs.cli.enable = true;
    };
    toh.test.commands.suffix = ''
      machine.succeed("toh")
    '';
  };
}
