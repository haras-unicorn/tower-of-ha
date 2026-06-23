{
  toh.lib.nixosModules.meta-cluster =
    {
      lib,
      config,
      options,
      ...
    }:
    let
      machineSubmodule =
        { lib, ... }:
        {
          options = options.toh.meta.machine // {
            meta = options.toh.meta;
            config = lib.mkOption {
              # TODO: use actual config type
              type = lib.types.raw;
              description = ''
                Machine NixOS configuration.
              '';
            };
          };
        };
    in
    {
      options.toh.meta = {
        cluster = {
          machines = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule machineSubmodule);
            default = { };
            description = ''
              Cluster machine attrset.
            '';
          };
          machinea = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule machineSubmodule);
            default = [ ];
            description = ''
              Cluster machine list.
            '';
          };
        };
      };
    };
}
