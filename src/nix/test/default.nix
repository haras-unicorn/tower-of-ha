{ selfLib, ... }:

{
  self.nixosTests.test = selfLib.test.makeNixosTest {
    containers.machine =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.hello ];
      };
    toh.test.commands.suffix = ''
      machine.succeed("hello")
    '';
  };
}
