{
  self.nixosModules.programs-cli.flake = true;
  self.nixosModules.programs-cli.value =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.programs.cli;
    in
    {
      options.toh.programs = {
        cli = {
          enable = lib.mkEnableOption "ToH CLI";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          pkgs.tohPackages.cli
        ];
      };
    };
}
