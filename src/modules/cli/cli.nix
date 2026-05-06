{
  toh.lib.nixosModules.programs-cli-cli =
    {
      tohLib,
      config,
      lib,
      ...
    }:
    let
      machines = builtins.mapAttrs (
        _: machine: builtins.removeAttrs machine [ "config" ]
      ) config.toh.cluster.machines;

      cluster = {
        inherit machines;
        machinea = builtins.attrValues machines;
      };

      ageKeyPathsPerMachine = builtins.mapAttrs (
        _: machine: machine.config.sops.age.defaultPath
      ) config.toh.cluster.machines;
    in
    {
      toh.overlays.cli-nixos = tohLib.cli.makeOverlay {
        extraRuntimeInputs = pkgs: [
          pkgs.gum
          pkgs.vault
          pkgs.tohPackages.flake-root
          pkgs.openssh
        ];
        loadExtraTextFromDir = ./.;
        extraTextVariables = builtins.mapAttrs (_: builtins.toJSON) {
          TOH_SOURCE = config.toh.meta.source;
          TOH_CLUSTER = cluster;
          TOH_LIB_SECRETS = tohLib.secrets;
          TOH_AGE_KEY_PATHS_PER_MACHINE = ageKeyPathsPerMachine;
        };
      };
    };
}
