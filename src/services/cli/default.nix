{ lib, self, ... }:

{
  overlayList = [
    {
      name = "cli-default";
      value = self.lib.cli.makeOverlay {
        extraRuntimeInputs = pkgs: [
          pkgs.gum
          pkgs.vault
        ];
        extraText =
          let
            scriptsText = builtins.concatStringsSep "\n\n" (
              builtins.map (script: builtins.readFile (lib.path.append ./. script)) (
                builtins.filter (lib.hasSuffix ".nu") (builtins.attrNames (builtins.readDir ./.))
              )
            );
          in
          ''
            $env.TOH_VAULT_CLUSTER = "${self.lib.cryl.directories.cluster}"

            ${scriptsText}
          '';
      };
    }
  ];

  perSystem =
    { lib, pkgs, ... }:
    let
      name = "toh";

      cli = pkgs.tohPackages.cli.override { inherit name; };

      cliApp = {
        type = "app";
        program = lib.getExe cli;
        meta.description = "${name} CLI";
      };
    in
    {
      packages = {
        inherit cli;
        default = cli;
      };

      apps = {
        cli = cliApp;
        default = cliApp;
      };

      checks.test-services-cli = pkgs.tohPackages.testers.runToHTest {
        name = "services-cli";
        nodes.machine = {
          imports = [ self.nixosModules.services-cli ];
        };
        toh.test.commands.suffix = ''
          machine.succeed("${name}")
        '';
      };
    };

  flake.nixosModules.services-cli =
    { pkgs, config, ... }:
    let
      capabilities = [
        "database"
        "domains"
        "locality"
        "network"
        "services"
      ];

      hosts = builtins.map (
        host:
        (lib.filterAttrs (name: _: name != "hosts" && name != "secrets" && name != "system") host)
        // (builtins.listToAttrs (
          builtins.filter builtins.isAttrs (
            builtins.map (
              capability:
              let
                raw = host.system.toh.${capability};
                # NOTE: need this because we can't be sure
                # if some of the options are always going to be set
                eval = builtins.tryEval (builtins.deepSeq raw raw);
              in
              if eval.success then
                {
                  name = capability;
                  value = eval.value;
                }
              else
                null
            ) capabilities
          )
        ))
      ) config.toh.host.hosts;

      hostsJson = builtins.toJSON hosts;
    in
    {
      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.cli
      ];

      environment.variables = {
        TOH_HOSTS = builtins.replaceStrings [ "\\" "\n" "\"" ] [ "\\\\" "\\n" "\\\"" ] hostsJson;
      };
    };
}
