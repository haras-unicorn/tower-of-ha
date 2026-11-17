{
  toh.lib.nixosModules.programs-cli =
    {
      pkgs,
      lib,
      tohLib,
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
