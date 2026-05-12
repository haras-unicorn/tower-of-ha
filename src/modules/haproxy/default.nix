{
  toh.lib.nixosModules.services-haproxy =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.haproxy;
      serviceDomain = config.toh.meta.domains.service;

      port = 443;

      serviceNamesToMachineServices = builtins.groupBy (service: service.name) (
        builtins.concatMap (machine: machine.meta.services) config.toh.cluster.machinea
      );

      certFile = config.sops.secrets."haproxy-pem".path;

      hostMap = builtins.toFile "host-map.map" (
        lib.concatMapStringsSep "\n" (serviceName: "${serviceName}.${serviceDomain} ${serviceName}") (
          builtins.attrNames serviceNamesToMachineServices
        )
      );

      frontend = ''
        frontend https_in
          bind :${builtins.toString port} ssl crt ${certFile}
          use_backend %[req.hdr(host),map_str(${hostMap})]
      '';

      backends = lib.concatStrings (
        lib.mapAttrsToList (
          serviceName: services:
          let
            serviceBackends = lib.concatMapStrings (
              service:
              "  server ${serviceName}-${service.address}"
              + " ${service.address}:${builtins.toString service.port}"
              + " ${if service.tls then "ssl verify none" else ""}\n"
            ) services;
          in
          ''
            backend ${serviceName}
              balance roundrobin
            ${serviceBackends}
          ''
        ) serviceNamesToMachineServices
      );
    in
    {
      options.toh.services = {
        haproxy = {
          enable = lib.mkEnableOption "HAProxy";
        };
      };

      config = lib.mkIf cfg.enable {
        services.haproxy = {
          enable = true;

          config = ''
            global
              daemon

            defaults
              mode http
              timeout connect 5s
              timeout client 30s
              timeout server 30s

            ${frontend}

            ${backends}
          '';
        };

        networking.firewall.allowedTCPPorts = [ port ];

        sops.secrets."haproxy-pem" = {
          owner = config.systemd.services.haproxy.serviceConfig.User;
          group = config.systemd.services.haproxy.serviceConfig.Group;
          mode = "0400";
        };

        toh.cryl.machine.haproxy = {
          generations = [
            {
              generator = "tls-leaf";
              arguments = {
                common_name = "toh";
                organization = "ToH";
                sans = [
                  "*.${config.toh.meta.domains.service}"
                  "localhost"
                  "${config.toh.meta.network.ip}"
                  "127.0.0.1"
                ];
                config = "haproxy-cert-config";
                request_config = "haproxy-cert-request-config";
                private = "haproxy-private";
                request = "haproxy-cert-request";
                ca_private = "cluster/openssl-ca-private";
                ca_public = "cluster/openssl-ca-public";
                serial = "cluster/openssl-ca-serial";
                public = "haproxy-public";
                renew = true;
              };
            }
            {
              generator = "script";
              arguments = {
                name = "haproxy-pem";
                renew = true;
                text = ''
                  (echo $"(open --raw haproxy-public)(open --raw haproxy-private)"
                    | save -f haproxy-pem)
                '';
              };
            }
          ];
        };

        toh.ssl.generateCa = true;
      };
    };
}
