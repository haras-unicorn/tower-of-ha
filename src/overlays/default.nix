{ lib, config, ... }:

{
  options.overlayList = lib.mkOption {
    default = [ ];
    description = "List of overlays with names and values";
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Overlay name";
          };
          value = lib.mkOption {
            type = lib.types.functionTo (lib.types.functionTo lib.types.raw);
            description = "Overlay value";
          };
        };
      }
    );
  };

  config = {
    flake.overlays = (builtins.listToAttrs config.overlayList) // {
      default = lib.composeManyExtensions (builtins.map ({ value, ... }: value) config.overlayList);
    };
  };
}
