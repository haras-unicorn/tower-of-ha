{ inputs, ... }:

let
  common =
    { lib, ... }:
    {
      options.toh = {
        cryl = {
          cluster = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification);
            default = { };
            description = ''
              Specifications in attrs for uniqueness
              that will be collected into a shared specification
              for the cluster
            '';
          };

          host = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification);
            default = { };
            description = ''
              Specifications in attrs for uniqueness
              that will be collected into a shared specification
              for the host
            '';
          };
        };
      };
    };
in
{
  flake.nixosModules.capabilities-secrets = {
    imports = [
      common
    ];
  };
}
