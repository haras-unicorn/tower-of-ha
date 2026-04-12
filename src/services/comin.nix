{ inputs, self, ... }:

{
  flake.nixosModules.services-comin =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.comin.nixosModules.comin
      ];

      services.comin = {
        enable = true;
        hostname = config.toh.host.name;
        remotes = [
          {
            name = "origin";
            url = "https://github.com/haras-unicorn/toh";
            branches.main.name = "main";
          }
        ];
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-comin = pkgs.tohPackages.testers.runToHTest {
        name = "services-comin";
        nodes.machine = {
          imports = [
            self.nixosModules.services-comin
          ];
        };
        toh.test.commands.suffix = ''
          machine.succeed("systemctl is-enabled comin.service")
          machine.succeed("which comin")
        '';
      };
    };
}
