{
  toh.lib.nixosModules.meta-impl =
    { config, tohLib, ... }:
    {
      toh.lib = {
        serviceMachines =
          service:
          builtins.filter (
            machine: machine.config.toh.services.${service}.enable
          ) config.toh.cluster.machinea;

        otherServiceMachines =
          service:
          builtins.filter (machine: machine.meta.network.ip != config.toh.meta.network.ip) (
            tohLib.serviceMachines service
          );

        serviceMachineIps =
          service: builtins.map (machine: machine.meta.network.ip) (tohLib.serviceMachines service);

        otherServiceMachineIps =
          service: builtins.map (machine: machine.meta.network.ip) (tohLib.otherServiceMachines service);

        anyServiceMachines =
          service:
          builtins.any (machine: machine.config.toh.services.${service}.enable) config.toh.cluster.machinea;
      };
    };
}
