{ selfLib, ... }:

{
  self.lib.cluster = {
    serviceMachines =
      config: service:
      builtins.filter (
        machine: machine.config.toh.services.${service}.enable
      ) config.toh.meta.cluster.machineList;

    otherServiceMachines =
      config: service:
      builtins.filter (machine: machine.meta.network.ip != config.toh.meta.network.ip) (
        selfLib.cluster.serviceMachines config service
      );

    anyServiceMachines =
      config: service:
      builtins.any (
        machine: machine.config.toh.services.${service}.enable
      ) config.toh.meta.cluster.machineList;

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
        machineList = builtins.attrValues machines;
      };
  };
}
