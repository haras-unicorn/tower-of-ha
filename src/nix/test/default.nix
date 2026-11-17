{
  perSystem =
    { pkgs, ... }:
    {
      checks.test-test = pkgs.tohPackages.testers.runToHTest {
        name = "Test test";
        nodes.machine =
          { pkgs, ... }:
          {
            environment.systemPackages = [ pkgs.hello ];
          };
        toh.test.commands.suffix = ''
          machine.succeed("hello")
        '';
      };
    };

  flake.tests = {
    test-test = {
      expr = true;
      expected = true;
    };
  };
}
