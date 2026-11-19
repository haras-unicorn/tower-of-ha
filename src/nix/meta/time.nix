{
  self.nixosModules.meta-time.flake = true;
  self.nixosModules.meta-time.value =
    { lib, config, ... }:
    let
      servingMachines = builtins.filter (
        machine: machine.meta.time.serve
      ) config.toh.meta.cluster.machineList;
    in
    {
      options.toh.meta.time = {
        serve = lib.mkEnableOption ''
          an NTP server on this machine, on the well-known NTP port, for the
          machines of the network
        '';

        servers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          default = builtins.map (machine: machine.meta.network.ip) servingMachines;
          defaultText = lib.literalExpression "addresses of the machines that serve time";
          description = ''
            Addresses of the NTP servers of the cluster. A machine that does
            not serve time takes its time from them when there are any.
          '';
        };
      };
    };
}
