{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks.test-services-cli = pkgs.tohPackages.testers.runToHTest {
        name = "services-cli";
        nodes.machine = {
          toh.programs.cli.enable = true;
        };
        toh.test.commands.suffix = ''
          machine.succeed("toh")
        '';
      };
    };
}
