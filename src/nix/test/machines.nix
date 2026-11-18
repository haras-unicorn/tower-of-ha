{ lib, ... }:

{
  self.lib.test.ofKind = kind: machines: {
    nodes = lib.mkIf (kind == "vm") machines;
    containers = lib.mkIf (kind == "container") machines;
  };

  self.lib.test.testModules.machines =
    {
      lib,
      nodes,
      containers,
      ...
    }:
    let
      machines = nodes // containers;
    in
    {
      options.toh.test = {
        kind = lib.mkOption {
          type = lib.types.enum [
            "container"
            "vm"
          ];
          default = "container";
          description = ''
            Whether the machines of the test are systemd-nspawn containers or
            QEMU VMs. The cluster nodes and the helper servers all follow it.
          '';
        };
      };

      config._module.args = {
        inherit machines;
        machineList = builtins.attrValues machines;
      };
    };
}
