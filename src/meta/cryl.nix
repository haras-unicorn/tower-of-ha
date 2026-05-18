{ inputs, ... }:

{
  toh.lib.nixosModules.meta-cryl =
    { lib, ... }:
    {
      options.toh = {
        cryl = {
          cluster = lib.mkOption {
            type = lib.types.listOf (
              lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification)
            );
            default = [ ];
            description = ''
              Specifications in lists of attrs for ordering and uniqueness
              that will be collected into a shared specification
              for the cluster
            '';
          };

          machine = lib.mkOption {
            type = lib.types.listOf (
              lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification)
            );
            default = [ ];
            description = ''
              Specifications in lists of attrs for ordering and uniqueness
              that will be collected into a shared specification
              for the machine
            '';
          };
        };
      };
    };
}
