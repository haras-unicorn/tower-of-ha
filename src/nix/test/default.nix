{ selfLib, ... }:

{
  self.nixosTests.test = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
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
