{
  perSystem =
    { lib, pkgs, ... }:
    let
      package = pkgs.tohPackages.cli;

      cliApp = {
        type = "app";
        program = lib.getExe package;
        meta.description = "ToH CLI";
      };
    in
    {
      packages.default = package;

      apps = {
        cli = cliApp;
        default = cliApp;
      };
    };
}
