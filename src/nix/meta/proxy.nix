{ selfLib, ... }:

{
  self.nixosModules.meta-proxy.flake = true;
  self.nixosModules.meta-proxy.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.meta.proxy;

      proxyMachines = builtins.filter (
        machine: machine.meta.proxy.enable
      ) config.toh.meta.cluster.machineList;

      serviceNamesToMachineServices = lib.zipAttrs (
        builtins.map (machine: machine.meta.services) config.toh.meta.cluster.machineList
      );

      makeProxy =
        serviceName: services:
        let
          endpointAttrs = selfLib.services.endpoint.toAttrs (builtins.head services).endpoint;
          isHttpBased = builtins.elem endpointAttrs.protocol [
            "http"
            "https"
          ];
          isSubmit = endpointAttrs.protocol == "submit";
          protocol =
            if isSubmit then
              "submit"
            else if isHttpBased then
              "https"
            else
              endpointAttrs.layer7Protocol;
        in
        {
          endpoint.${protocol} = {
            host =
              if isSubmit then
                config.toh.meta.email.domain
              else
                "${serviceName}.${config.toh.meta.domains.service}";
            port =
              if isSubmit then
                cfg.ports.submit
              else if isHttpBased then
                cfg.ports.https
              else
                endpointAttrs.port + cfg.ports.tcpOffset;
          };
        };
    in
    {
      options.toh.meta.proxy = {
        enable = lib.mkEnableOption ''
          a proxy on this machine that serves every address in
          `toh.meta.proxies`
        '';

        ports = {
          https = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = ''
              Proxy port of every HTTP and HTTPS service. The proxy tells them
              apart by host name.
            '';
          };

          submit = lib.mkOption {
            type = lib.types.port;
            default = 25;
            description = "Proxy port of mail submission.";
          };

          tcpOffset = lib.mkOption {
            type = lib.types.port;
            default = 10000;
            description = ''
              Added to the port of a TCP service to give its port on the proxy.
            '';
          };
        };
      };

      config = lib.mkIf (proxyMachines != [ ]) {
        toh.meta.relays = builtins.map (machine: machine.meta.network.ip) proxyMachines;
        toh.meta.proxies = builtins.mapAttrs makeProxy serviceNamesToMachineServices;
      };
    };
}
