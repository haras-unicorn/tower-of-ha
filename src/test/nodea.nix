{
  toh.lib.test.testModules.nodea =
    { nodes, ... }:
    {
      _module.args.nodea = builtins.attrValues nodes;
    };
}
