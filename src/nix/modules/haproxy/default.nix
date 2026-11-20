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

{ selfLib, ... }:

{
  self.nixosModules.services-haproxy.flake = true;
  self.nixosModules.services-haproxy.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.haproxy;

      certFile = config.toh.meta.sops.secrets."haproxy-pem".path;
      caFile = config.toh.meta.sops.secrets."haproxy-ca-public".path;

      httpPort = config.toh.meta.proxy.ports.https;
      submitPort = config.toh.meta.proxy.ports.submit;

      proxyAttrs =
        serviceName: selfLib.services.endpoint.toAttrs config.toh.meta.proxies.${serviceName}.endpoint;

      proxyHosts = lib.unique (
        builtins.map (serviceName: (proxyAttrs serviceName).host) (
          builtins.attrNames config.toh.meta.proxies
        )
      );

      serviceNamesToMachineServices = lib.zipAttrs (
        builtins.map (machine: machine.meta.services) config.toh.meta.cluster.machineList
      );

      filterServiceNamesToMachineNames =
        protocols:
        lib.filterAttrs (
          _: services:
          builtins.all (
            service:
            let
              endpointAttrs = selfLib.services.endpoint.toAttrs service.endpoint;
            in
            builtins.elem endpointAttrs.protocol protocols
          ) services
        ) serviceNamesToMachineServices;

      httpServiceNamesToMachineServices = filterServiceNamesToMachineNames [
        "http"
        "https"
      ];

      submitServiceMachineServices = builtins.concatLists (
        builtins.attrValues (filterServiceNamesToMachineNames [
          "submit"
        ])
      );

      tcpServiceNamesToMachineServices = filterServiceNamesToMachineNames [
        "tcp"
      ];

      escape = string: builtins.replaceStrings [ "\n" "\r" " " "\t" ] [ "\\n" "\\r" "\\ " "\\t" ] string;

      makeServerBlock =
        serviceName: service:
        let
          healthAttrs = selfLib.services.endpoint.toAttrs service.health.endpoint;
          endpointAttrs = selfLib.services.endpoint.toAttrs service.endpoint;
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
              # NOTE: since 3.3, haproxy sends the request host as SNI and
              # verifies the server certificate against it, but service
              # certificates name the machine and not the service
              "ssl verify required ca-file ${caFile} crt ${certFile} no-sni-auto"
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
          healthAttrs = selfLib.services.endpoint.toAttrs service.health.endpoint;
          isHealthHttp = builtins.elem healthAttrs.protocol [
            "http"
            "https"
          ];
          isHealthTcp = healthAttrs.protocol == "tcp";
          healthUri =
            if healthAttrs.path != null then "uri /${lib.removePrefix "/" healthAttrs.path}" else "";
        in
        lib.optionalString (service.health.endpoint != null) (
          if isHealthHttp then
            "option httpchk"
            + "\nhttp-check connect linger"
            + lib.optionalString (healthAttrs.protocol == "https") " ssl"
            + "\nhttp-check send meth ${healthAttrs.method} ${healthUri} hdr host ${healthAttrs.host}"
            + "\nhttp-check expect status ${builtins.toString healthAttrs.status}"
          else
            "option tcp-check"
            + "\ntcp-check connect linger"
            + lib.optionalString healthAttrs.ssl " ssl"
            + lib.optionalString isHealthTcp (
              builtins.concatStringsSep "" (
                builtins.map (
                  { send, expect }:
                  let
                    hasSend = send != null;
                    hasExpect = expect != null;

                    expectType = if selfLib.regex.isRegex expect then "rstring" else "string";
                  in
                  lib.optionalString hasSend "\ntcp-check send ${escape send}"
                  + lib.optionalString hasExpect "\ntcp-check expect ${expectType} ${escape expect}"
                ) healthAttrs.packets
              )
            )
        );

      makePersistenceBlock =
        serviceName: services:
        let
          firstService = builtins.head services;
          endpointAttrs = selfLib.services.endpoint.toAttrs firstService.endpoint;
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

      proxiedHttpServiceNames = builtins.attrNames (
        lib.filterAttrs (
          _: services: selfLib.services.routeOf (builtins.head services) == null
        ) httpServiceNamesToMachineServices
      );

      httpHostMap = builtins.toFile "toh-service-http-host-map.map" (
        lib.concatMapStringsSep "\n" (
          serviceName: "${(proxyAttrs serviceName).host} ${serviceName}"
        ) proxiedHttpServiceNames
      );

      # NOTE: haproxy tries the use_backend rules in the order they are
      # written, which is the order routes are sorted in; its regular
      # expressions find a match anywhere in the path, so they are wrapped
      # to match the whole path like the routes of every other proxy do
      makePathCondition =
        path:
        if path ? prefix then "path_beg ${escape path.prefix}" else "path_reg ^(${escape path.regex})$";

      # NOTE: the host header may name the port, even the default one, so
      # the rules match only what comes before the colon
      requestHost = "req.hdr(host),field(1,:)";

      makeRouteRule =
        route:
        let
          hostAcl = "route_${route.name}_host";
          pathAcl = "route_${route.name}_path";
        in
        ''
          acl ${hostAcl} ${requestHost} -m str ${(proxyAttrs route.service).host}
          ${lib.concatMapStringsSep "\n" (path: "acl ${pathAcl} ${makePathCondition path}") route.paths}
          use_backend ${route.name} if ${hostAcl} ${pathAcl}
        '';

      routeRules = lib.concatMapStringsSep "\n" makeRouteRule (
        selfLib.services.routes httpServiceNamesToMachineServices
      );

      httpFrontend = ''
        frontend http_any
          mode http
          bind ${config.toh.meta.network.ip}:${builtins.toString httpPort} ssl crt ${certFile}
          bind 127.0.0.1:${builtins.toString httpPort} ssl crt ${certFile}
          ${selfLib.strings.indentTail "  " routeRules}
          use_backend %[${requestHost},map_str(${httpHostMap})]
          http-request set-header X-Forwarded-Proto https
      '';

      httpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            mode http
            balance roundrobin

            ${selfLib.strings.indentTail "  " (makePersistenceBlock serviceName services)}

            ${selfLib.strings.indentTail "  " (makeCheckBlock serviceName services)}

            ${selfLib.strings.indentTail "  " (makeServersBlock serviceName services)}
        '') httpServiceNamesToMachineServices
      );

      tcpFrontends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (
          serviceName: services:
          let
            service = builtins.head services;
            endpointAttrs = selfLib.services.endpoint.toAttrs service.endpoint;
            ssl = lib.optionalString (builtins.elem endpointAttrs.sslTermination [
              "re-encrypt"
              "terminate"
            ]) "ssl crt ${certFile}";
          in
          ''
            frontend tcp_${serviceName}
              mode tcp
              bind ${config.toh.meta.network.ip}:${builtins.toString (proxyAttrs serviceName).port} ${ssl}
              bind 127.0.0.1:${builtins.toString (proxyAttrs serviceName).port} ${ssl}
              default_backend ${serviceName}
          ''
        ) tcpServiceNamesToMachineServices
      );

      tcpBackends = builtins.concatStringsSep "\n\n" (
        lib.mapAttrsToList (serviceName: services: ''
          backend ${serviceName}
            mode tcp
            balance leastconn

            ${selfLib.strings.indentTail "  " (makePersistenceBlock serviceName services)}

            ${selfLib.strings.indentTail "  " (makeCheckBlock serviceName services)}

            ${selfLib.strings.indentTail "  " (makeServersBlock serviceName services)}
        '') tcpServiceNamesToMachineServices
      );

      submitFrontend = lib.optionalString (submitServiceMachineServices != [ ]) ''
        frontend submit_any
          mode tcp
          bind ${config.toh.meta.network.ip}:${builtins.toString submitPort} ssl crt ${certFile}
          bind 127.0.0.1:${builtins.toString submitPort} ssl crt ${certFile}
          default_backend submit_backend
      '';

      submitBackend = lib.optionalString (submitServiceMachineServices != [ ]) ''
        backend submit_backend
          mode tcp
          balance leastconn

          ${selfLib.strings.indentTail "  " (makePersistenceBlock "submit" submitServiceMachineServices)}

          ${selfLib.strings.indentTail "  " (makeCheckBlock "submit" submitServiceMachineServices)}

          ${selfLib.strings.indentTail "  " (makeServersBlock "submit" submitServiceMachineServices)}
      '';
    in
    {
      options.toh.services = {
        haproxy = {
          enable = lib.mkEnableOption "HAProxy";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.meta.proxy.enable = true;

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

            ${submitFrontend}

            ${submitBackend}
          '';
        };

        networking.firewall.allowedTCPPorts = [
          httpPort
          submitPort
        ]
        ++ (builtins.map (serviceName: (proxyAttrs serviceName).port) (
          builtins.attrNames tcpServiceNamesToMachineServices
        ));

        toh.meta.sops.secrets."haproxy-ca-public" = {
          key = "openssl-ca-public";
          owner = config.systemd.services.haproxy.serviceConfig.User;
          group = config.systemd.services.haproxy.serviceConfig.Group;
          mode = "0400";
        };

        toh.meta.sops.secrets."haproxy-pem" = {
          owner = config.systemd.services.haproxy.serviceConfig.User;
          group = config.systemd.services.haproxy.serviceConfig.Group;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
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
                    ]
                    ++ proxyHosts;
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

        toh.pki.installCa = true;
      };
    };
}
