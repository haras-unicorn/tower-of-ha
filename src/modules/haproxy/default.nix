# TODO: switch to proxying to other proxies
# if the service is not on this machine with a secure connection
# and proxying to localhost with the actual configured connection
# when the service is on localhost
# with a huge weight for it and lesser weights for other proxies
# the weights should go only to proxies that are on machines
# with the service in the following order:
# 1. this machine
# 2. my rack
# 3. my datacenter
# 4. my region
# 5. other regions

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

      certFile = config.sops.secrets."haproxy-pem".path;
      caFile = config.sops.secrets."haproxy-ca-public".path;

      httpPort = 443;

      tcpPortOffset = 10000;

      machines = tohLib.serviceMachines "haproxy";

      mapTcpPortFromServices =
        services: (tohLib.services.endpoint.toAttrs (builtins.head services).endpoint).port + tcpPortOffset;

      serviceNamesToMachineServices = lib.zipAttrs (
        builtins.map (machine: machine.meta.services) config.toh.cluster.machinea
      );

      httpServiceNamesToMachineServices = lib.filterAttrs (
        _: services:
        builtins.all (
          service:
          let
            endpointAttrs = tohLib.services.endpoint.toAttrs service.endpoint;
          in
          builtins.elem endpointAttrs.protocol [
            "http"
            "https"
          ]
        ) services
      ) serviceNamesToMachineServices;

      tcpServiceNamesToMachineServices = lib.filterAttrs (
        _: services:
        builtins.all (
          service:
          let
            endpointAttrs = tohLib.services.endpoint.toAttrs service.endpoint;
          in
          builtins.elem endpointAttrs.protocol [
            "tcp"
          ]
        ) services
      ) serviceNamesToMachineServices;

      makeServerBlock =
        serviceName: service:
        let
          healthAttrs = tohLib.services.endpoint.toAttrs service.health.endpoint;
          endpointAttrs = tohLib.services.endpoint.toAttrs service.endpoint;
          check = lib.optionalString (service.health.endpoint != null) (
            "check" + " port ${builtins.toString healthAttrs.port}" + " addr ${healthAttrs.host}"
          );
          ssl =
            if
              if endpointAttrs ? sslTermination then
                endpointAttrs.sslTermination == "re-encrypt"
              else
                endpointAttrs.protocol == "https"
            then
              "ssl verify required ca-file ${caFile} crt ${certFile}"
            else
              "verify required ca-file ${caFile} crt ${certFile}";
        in
        "server ${serviceName}-${endpointAttrs.host}"
        + " ${endpointAttrs.host}:${builtins.toString endpointAttrs.port}"
        + " ${ssl}"
        + " ${check}";

      makeServersBlock =
        serviceName: services: lib.concatMapStringsSep "\n" (makeServerBlock serviceName) services;

      makeCheckBlock =
        serviceName: services:
        let
          service = builtins.head services;
          healthAttrs = tohLib.services.endpoint.toAttrs service.health.endpoint;
          isHealthHttp = builtins.elem healthAttrs.protocol [
            "http"
            "https"
          ];
          healthUri =
            if healthAttrs.path != null then "uri /${lib.removePrefix "/" healthAttrs.path}" else "";
        in
        lib.optionalString (service.health.endpoint != null) (
          if isHealthHttp then
            "option httpchk"
            + "\nhttp-check connect linger"
            + lib.optionalString (healthAttrs.protocol == "https") " ssl"
            + "\nhttp-check send meth ${healthAttrs.method} ${healthUri}"
            + "\nhttp-check expect status ${builtins.toString healthAttrs.status}"
          else
            "option tcp-check" + "\ntcp-check connect linger" + lib.optionalString healthAttrs.ssl " ssl"
        );

      makePersistenceBlock =
        serviceName: services:
        let
          firstService = builtins.head services;
          endpointAttrs = tohLib.services.endpoint.toAttrs firstService.endpoint;
        in
        if endpointAttrs ? persistIp && endpointAttrs.persistIp then
          ''
            stick-table type ip size 1m expire 30m
            stick on src
          ''
        else if endpointAttrs ? persistCookie && endpointAttrs.persistCookie != null then
          ''
            cookie ${endpointAttrs.persistCookie} insert indirect nocache
            stick-table type string len 32 size 1m expire 30m
            stick on cookie(${endpointAttrs.persistCookie})
          ''
        else
          "";

      httpHostMap = builtins.toFile "toh-service-http-host-map.map" (
        lib.concatMapStringsSep "\n" (serviceName: "${serviceName}.${serviceDomain} ${serviceName}") (
          builtins.attrNames httpServiceNamesToMachineServices
        )
      );

      httpFrontend = ''
        frontend http_any
          mode http
          bind ${config.toh.meta.network.ip}:${builtins.toString httpPort} ssl crt ${certFile}
          bind 127.0.0.1:${builtins.toString httpPort} ssl crt ${certFile}
          use_backend %[req.hdr(host),map_str(${httpHostMap})]
      '';

      httpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            mode http
            balance roundrobin

            ${tohLib.strings.indentTail "  " (makePersistenceBlock serviceName services)}

            ${tohLib.strings.indentTail "  " (makeCheckBlock serviceName services)}

            ${tohLib.strings.indentTail "  " (makeServersBlock serviceName services)}
        '') httpServiceNamesToMachineServices
      );

      tcpFrontends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (
          serviceName: services:
          let
            service = builtins.head services;
            endpointAttrs = tohLib.services.endpoint.toAttrs service.endpoint;
            ssl = lib.optionalString (builtins.elem endpointAttrs.sslTermination [
              "re-encrypt"
              "terminate"
            ]) "ssl crt ${certFile}";
          in
          ''
            frontend tcp_${serviceName}
              mode tcp
              bind ${config.toh.meta.network.ip}:${builtins.toString (mapTcpPortFromServices services)} ${ssl}
              bind 127.0.0.1:${builtins.toString (mapTcpPortFromServices services)} ${ssl}
              default_backend ${serviceName}
          ''
        ) tcpServiceNamesToMachineServices
      );

      tcpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            mode tcp
            balance leastconn

            ${tohLib.strings.indentTail "  " (makePersistenceBlock serviceName services)}

            ${tohLib.strings.indentTail "  " (makeCheckBlock serviceName services)}

            ${tohLib.strings.indentTail "  " (makeServersBlock serviceName services)}
        '') tcpServiceNamesToMachineServices
      );
    in
    {
      options.toh.services = {
        haproxy = {
          enable = lib.mkEnableOption "HAProxy";
        };
      };

      config = lib.mkMerge [
        {
          toh.meta.relays = builtins.map (machine: machine.meta.network.ip) machines;
        }
        (lib.mkIf (machines != [ ]) {
          toh.meta.proxies = builtins.mapAttrs (
            serviceName: services:
            let
              service = builtins.head services;
              endpointAttrs = tohLib.services.endpoint.toAttrs service.endpoint;
              isHttpBased = builtins.elem endpointAttrs.protocol [
                "http"
                "https"
              ];
              protocol = if isHttpBased then "https" else endpointAttrs.layer7Protocol;
            in
            {
              endpoint.${protocol} = {
                host = "${serviceName}.${serviceDomain}";
                port = if isHttpBased then httpPort else mapTcpPortFromServices services;
              };
            }
          ) serviceNamesToMachineServices;
        })
        (lib.mkIf cfg.enable {
          services.haproxy = {
            enable = true;

            config = ''
              global
                daemon

              defaults
                timeout connect 5s
                timeout client 30s
                timeout server 30s

              ${httpFrontend}

              ${httpBackends}

              ${tcpFrontends}

              ${tcpBackends}
            '';
          };

          networking.firewall.allowedTCPPorts = [
            httpPort
          ]
          ++ (builtins.map mapTcpPortFromServices (builtins.attrValues tcpServiceNamesToMachineServices));

          sops.secrets."haproxy-ca-public" = {
            key = "openssl-ca-public";
            owner = config.systemd.services.haproxy.serviceConfig.User;
            group = config.systemd.services.haproxy.serviceConfig.Group;
            mode = "0400";
          };

          sops.secrets."haproxy-pem" = {
            owner = config.systemd.services.haproxy.serviceConfig.User;
            group = config.systemd.services.haproxy.serviceConfig.Group;
            mode = "0400";
          };

          toh.cryl.machine = [
            {
              haproxy = {
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
                      name = "haproxy-pem-script";
                      renew = true;
                      text = ''
                        (echo $"(open --raw haproxy-public)(open --raw haproxy-private)"
                          | save -f haproxy-pem)
                      '';
                    };
                  }
                ];
              };
            }
          ];

          toh.ssl.installCa = true;
        })
      ];
    };
}
