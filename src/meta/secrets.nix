{ inputs, ... }:

{
  toh.lib.nixosModules.meta-secrets =
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

          machine = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule inputs.cryl.lib.submodules.specification);
            default = { };
            description = ''
              Specifications in attrs for uniqueness
              that will be collected into a shared specification
              for the machine
            '';
          };
        };
      };
    };
}
