{ config, inputs, ... }:

let
  flakeOverlays = config.self.overlays.overlays;

  namespace = config.self.overlays.namespace;

  overlaysLib = inputs.haraspkgs.lib.overlays;
in
{
  # NOTE: modules add CLI parts that depend on the machine config, so the
  # overlay graph has to exist at the NixOS level too; haraspkgs only has
  # one at the flake level, so this reuses its graph helpers
  self.nixosModules.meta-overlays.flake = true;
  self.nixosModules.meta-overlays.value =
    { lib, config, ... }:
    {
      options.toh.overlays = lib.mkOption {
        default = { };
        description = ''
          Overlays composed into `pkgs.tohPackages`, on top of the ones of the
          flake.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  description = "Overlay name.";
                };

                deps = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Overlay dependencies, as exact names or slash-delimited regexes.";
                };

                value = lib.mkOption {
                  type = lib.types.functionTo (lib.types.functionTo lib.types.attrs);
                  description = "Overlay function, `final: prev: attrs`.";
                };
              };
            }
          )
        );
      };

      config = {
        toh.overlays = builtins.mapAttrs (_: overlay: { inherit (overlay) deps value; }) flakeOverlays;

        nixpkgs.overlays = [
          (overlaysLib.namespaceOverlay namespace (
            overlaysLib.composeOverlay config.toh.overlays config.toh.overlays
          ))
        ];
      };
    };
}
