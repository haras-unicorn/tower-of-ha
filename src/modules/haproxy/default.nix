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
          healthUri = if healthAttrs.path != null then "uri /${healthAttrs.path}" else "";
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

      httpHostMap = builtins.toFile "toh-service-http-host-map.map" (
        lib.concatMapStringsSep "\n" (serviceName: "${serviceName}.${serviceDomain} ${serviceName}") (
          builtins.attrNames httpServiceNamesToMachineServices
        )
      );

      httpFrontend = ''
        frontend http_any
          bind ${config.toh.meta.network.ip}:${builtins.toString httpPort} ssl crt ${certFile}
          use_backend %[req.hdr(host),map_str(${httpHostMap})]
      '';

      httpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            balance roundrobin

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
              default_backend ${serviceName}
          ''
        ) tcpServiceNamesToMachineServices
      );

      tcpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            mode tcp
            balance leastconn

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
        (lib.mkIf cfg.enable {
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
            }
          ];

          toh.ssl.installCa = true;
        })
      ];
    };
}
