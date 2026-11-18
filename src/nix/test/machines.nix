{
  self.lib.test.testModules.machines =
    { nodes, containers, ... }:
    let
      machines = nodes // containers;
    in
    {
      _module.args = {
        inherit machines;
        machineList = builtins.attrValues machines;
      };
    };
}
