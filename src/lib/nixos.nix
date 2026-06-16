{ tohLib, ... }:

{
  toh.lib.nixosModules.lib-impl =
    { config, tohLib, ... }:
    {
      toh.lib = {
        serviceMachines =
          service:
          builtins.filter (
            machine: machine.config.toh.services.${service}.enable
          ) config.toh.meta.cluster.machinea;

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
          builtins.any (
            machine: machine.config.toh.services.${service}.enable
          ) config.toh.meta.cluster.machinea;
      };
    };

  toh.lib.nixosModules.lib =
    { config, lib, ... }:
    {
      options.toh = {
        lib = lib.mkOption {
          type = tohLib.types.recursiveAttrsOf lib.types.raw;
          default = { };
          description = "ToH library merged attrset";
        };
      };

      config = {
        _module.args.tohLib = config.toh.lib;

        toh.lib = tohLib;
      };
    };
}
