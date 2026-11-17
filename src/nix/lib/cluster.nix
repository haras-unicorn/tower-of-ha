{
  toh.lib.cluster = {
    fromTestNodes =
      nodes:
      let
        machines = builtins.mapAttrs (
          _: node:
          node.toh.meta.machine
          // {
            meta = node.toh.meta;
            config = node;
          }
        ) nodes;
      in
      {
        inherit machines;
        machinea = builtins.attrValues machines;
      };
  };
}
