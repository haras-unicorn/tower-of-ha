{ selfLib, ... }:

{
  self.nixosModules.services-envoy.flake = true;
  self.nixosModules.services-envoy.value =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.toh.services.envoy;

      # NOTE: the nixpkgs module runs envoy as a dynamic user, which no file
      # can be owned by, so systemd hands it the certificates as credentials
      credentialsDirectory = "/run/credentials/envoy.service";
      certFile = "${credentialsDirectory}/cert";
      keyFile = "${credentialsDirectory}/key";
      caFile = "${credentialsDirectory}/ca";

      httpsPort = config.toh.meta.proxy.ports.https;
      submitPort = config.toh.meta.proxy.ports.submit;

      toAttrs = selfLib.services.endpoint.toAttrs;

      proxyAttrs = serviceName: toAttrs config.toh.meta.proxies.${serviceName}.endpoint;

      proxyHosts = lib.unique (
        builtins.map (serviceName: (proxyAttrs serviceName).host) (
          builtins.attrNames config.toh.meta.proxies
        )
      );

      serviceNamesToMachineServices = lib.zipAttrs (
        builtins.map (machine: machine.meta.services) config.toh.meta.cluster.machineList
      );

      servicesOf =
        protocols:
        lib.filterAttrs (
          _: services:
          builtins.all (service: builtins.elem (toAttrs service.endpoint).protocol protocols) services
        ) serviceNamesToMachineServices;

      httpServices = servicesOf [
        "http"
        "https"
      ];

      tcpServices = servicesOf [ "tcp" ];

      submitServices = builtins.concatLists (builtins.attrValues (servicesOf [ "submit" ]));

      proxiedHttpServiceNames = builtins.attrNames (
        lib.filterAttrs (
          _: services: selfLib.services.routeOf (builtins.head services) == null
        ) httpServices
      );

      routes = selfLib.services.routes httpServices;

      socketAddress = host: port: {
        socket_address = {
          address = host;
          port_value = port;
        };
      };

      isIp = host: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" host != null;

      certificate = {
        certificate_chain.filename = certFile;
        private_key.filename = keyFile;
      };

      downstreamTls = {
        name = "envoy.transport_sockets.tls";
        typed_config = {
          "@type" = "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext";
          common_tls_context.tls_certificates = [ certificate ];
        };
      };

      # NOTE: no SNI and no name check, because service certificates name
      # the machine and not the service, so envoy only checks that the
      # cluster CA signed them
      upstreamTls = {
        name = "envoy.transport_sockets.tls";
        typed_config = {
          "@type" = "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext";
          common_tls_context = {
            tls_certificates = [ certificate ];
            validation_context.trusted_ca.filename = caFile;
          };
        };
      };

      upstreamPlain = {
        name = "envoy.transport_sockets.raw_buffer";
        typed_config."@type" =
          "type.googleapis.com/envoy.extensions.transport_sockets.raw_buffer.v3.RawBuffer";
      };

      isBackendTls =
        endpointAttrs:
        if endpointAttrs ? sslTermination then
          endpointAttrs.sslTermination == "re-encrypt"
        else
          endpointAttrs.protocol == "https";

      isHealthTls =
        healthAttrs: if healthAttrs ? ssl then healthAttrs.ssl else healthAttrs.protocol == "https";

      isHttpBased =
        protocol:
        builtins.elem protocol [
          "http"
          "https"
        ];

      # NOTE: a health check may speak TLS when the traffic does not, or the
      # other way round, so every cluster has a socket of each kind for its
      # health check to pick, and the traffic keeps the default socket
      healthSockets = [
        {
          name = "health-tls";
          match.health = "tls";
          transport_socket = upstreamTls;
        }
        {
          name = "health-plain";
          match.health = "plain";
          transport_socket = upstreamPlain;
        }
      ];

      makeHealthCheck =
        service:
        let
          healthAttrs = toAttrs service.health.endpoint;
          packets = healthAttrs.packets or [ ];
          sends = builtins.concatStringsSep "" (
            builtins.filter (send: send != null) (builtins.map (packet: packet.send) packets)
          );
          expects = builtins.filter (expect: expect != null) (builtins.map (packet: packet.expect) packets);
        in
        {
          timeout = cfg.health.timeout;
          interval = cfg.health.interval;
          # NOTE: by default a cluster without traffic is checked only once
          # a minute, so a backend would come back that much later
          no_traffic_interval = cfg.health.interval;
          healthy_threshold = cfg.health.healthyThreshold;
          unhealthy_threshold = cfg.health.unhealthyThreshold;
          # NOTE: a server like SSH greets only once per connection, so every
          # check needs a connection of its own
          reuse_connection = false;
          transport_socket_match_criteria.health = if isHealthTls healthAttrs then "tls" else "plain";
        }
        // (
          if isHttpBased healthAttrs.protocol then
            {
              http_health_check = {
                host = healthAttrs.host;
                path = "/" + lib.removePrefix "/" (if healthAttrs.path != null then healthAttrs.path else "");
                method = healthAttrs.method;
                expected_statuses = [
                  {
                    start = healthAttrs.status;
                    end = healthAttrs.status + 1;
                  }
                ];
              };
            }
          else
            {
              tcp_health_check = {
                receive = builtins.map (expect: { text = selfLib.strings.toHex expect; }) expects;
              }
              // lib.optionalAttrs (sends != "") {
                send.text = selfLib.strings.toHex sends;
              };
            }
        );

      makeLbEndpoint =
        service:
        let
          endpointAttrs = toAttrs service.endpoint;
          healthAttrs = toAttrs service.health.endpoint;
        in
        {
          endpoint = {
            address = socketAddress endpointAttrs.host endpointAttrs.port;
          }
          // lib.optionalAttrs (service.health.endpoint != null) {
            health_check_config = {
              port_value = healthAttrs.port;
            }
            // lib.optionalAttrs (healthAttrs.host != endpointAttrs.host) {
              address = socketAddress healthAttrs.host healthAttrs.port;
            };
          };
        };

      isPersistent =
        endpointAttrs: (endpointAttrs.persistIp or false) || (endpointAttrs.persistCookie or null) != null;

      makeCluster =
        lbPolicy: name: services:
        let
          firstService = builtins.head services;
          endpointAttrs = toAttrs firstService.endpoint;
          hosts = builtins.map (service: (toAttrs service.endpoint).host) services;
        in
        {
          inherit name;
          type = if builtins.all isIp hosts then "STATIC" else "STRICT_DNS";
          dns_lookup_family = "V4_ONLY";
          connect_timeout = cfg.timeouts.connect;
          lb_policy = if isPersistent endpointAttrs then "RING_HASH" else lbPolicy;
          # NOTE: by default envoy sends to every backend once fewer than
          # half of them are healthy, and a service like Valkey has only one
          # healthy backend, its master, out of many
          common_lb_config.healthy_panic_threshold.value = 0;
          load_assignment = {
            cluster_name = name;
            endpoints = [ { lb_endpoints = builtins.map makeLbEndpoint services; } ];
          };
          health_checks = lib.optional (firstService.health.endpoint != null) (makeHealthCheck firstService);
          transport_socket_matches = healthSockets;
        }
        // lib.optionalAttrs (isBackendTls endpointAttrs) {
          transport_socket = upstreamTls;
        };

      makeListener =
        {
          name,
          port,
          filters,
          tls,
        }:
        {
          inherit name;
          address = socketAddress config.toh.meta.network.ip port;
          additional_addresses = [ { address = socketAddress "127.0.0.1" port; } ];
          # NOTE: envoy may start before the VPN gives this machine its
          # address
          freebind = true;
          filter_chains = [
            (
              {
                inherit filters;
              }
              // lib.optionalAttrs tls {
                transport_socket = downstreamTls;
              }
            )
          ];
        };

      makeRouteAction =
        name:
        let
          endpointAttrs = toAttrs (builtins.head httpServices.${name}).endpoint;
        in
        {
          cluster = name;
          # NOTE: long polls like the Matrix sync hold a request open, so a
          # request has no deadline and only the idle timeout ends it
          timeout = "0s";
          idle_timeout = cfg.timeouts.idle;
        }
        // lib.optionalAttrs ((endpointAttrs.persistCookie or null) != null) {
          hash_policy = [
            {
              cookie = {
                name = endpointAttrs.persistCookie;
                ttl = cfg.persistence.ttl;
              };
            }
          ];
        };

      makePathMatch =
        path: if path ? prefix then { prefix = path.prefix; } else { safe_regex.regex = path.regex; };

      makeVirtualHost =
        serviceName:
        let
          routesOfHost = builtins.filter (route: route.service == serviceName) routes;
        in
        {
          name = serviceName;
          domains = [ (proxyAttrs serviceName).host ];
          routes =
            builtins.concatMap (
              route:
              builtins.map (path: {
                match = makePathMatch path;
                route = makeRouteAction route.name;
              }) route.paths
            ) routesOfHost
            ++ [
              {
                match.prefix = "/";
                route = makeRouteAction serviceName;
              }
            ];
        };

      httpConnectionManager = {
        name = "envoy.filters.network.http_connection_manager";
        typed_config = {
          "@type" =
            "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager";
          stat_prefix = "https";
          # NOTE: the host header may name the port, even the default one,
          # so the virtual hosts match only what comes before the colon
          strip_any_host_port = true;
          upgrade_configs = [ { upgrade_type = "websocket"; } ];
          route_config = {
            name = "https";
            virtual_hosts = builtins.map makeVirtualHost proxiedHttpServiceNames;
            request_headers_to_add = [
              {
                header = {
                  key = "x-forwarded-proto";
                  value = "https";
                };
                append_action = "OVERWRITE_IF_EXISTS_OR_ADD";
              }
            ];
          };
          http_filters = [
            {
              name = "envoy.filters.http.router";
              typed_config."@type" = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router";
            }
          ];
        };
      };

      makeTcpProxy =
        name: services:
        let
          endpointAttrs = toAttrs (builtins.head services).endpoint;
        in
        {
          name = "envoy.filters.network.tcp_proxy";
          typed_config = {
            "@type" = "type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy";
            stat_prefix = name;
            cluster = name;
            idle_timeout = cfg.timeouts.idle;
          }
          // lib.optionalAttrs (endpointAttrs.persistIp or false) {
            hash_policy = [ { source_ip = { }; } ];
          };
        };

      isTerminated =
        services:
        builtins.elem (toAttrs (builtins.head services).endpoint).sslTermination [
          "re-encrypt"
          "terminate"
        ];

      httpsListener = makeListener {
        name = "https";
        port = httpsPort;
        filters = [ httpConnectionManager ];
        tls = true;
      };

      tcpListeners = lib.mapAttrsToList (
        name: services:
        makeListener {
          name = "tcp-${name}";
          port = (proxyAttrs name).port;
          filters = [ (makeTcpProxy name services) ];
          tls = isTerminated services;
        }
      ) tcpServices;

      submitListeners = lib.optional (submitServices != [ ]) (makeListener {
        name = "submit";
        port = submitPort;
        filters = [ (makeTcpProxy "submit" submitServices) ];
        tls = isTerminated submitServices;
      });

      adminClusterName = "envoy-admin";

      adminCluster = {
        name = adminClusterName;
        type = "STATIC";
        connect_timeout = cfg.timeouts.connect;
        load_assignment = {
          cluster_name = adminClusterName;
          endpoints = [
            {
              lb_endpoints = [ { endpoint.address = socketAddress "127.0.0.1" cfg.adminPort; } ];
            }
          ];
        };
      };

      # NOTE: the admin interface can also change and stop the proxy, so the
      # collectors on other machines reach only its metrics, through a
      # listener of its own
      statsPath = "/stats/prometheus";

      statsListener = {
        name = "stats";
        address = socketAddress config.toh.meta.network.ip cfg.statsPort;
        freebind = true;
        filter_chains = [
          {
            filters = [
              {
                name = "envoy.filters.network.http_connection_manager";
                typed_config = {
                  "@type" =
                    "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager";
                  stat_prefix = "stats";
                  route_config = {
                    name = "stats";
                    virtual_hosts = [
                      {
                        name = "stats";
                        domains = [ "*" ];
                        routes = [
                          {
                            match.path = statsPath;
                            route.cluster = adminClusterName;
                          }
                          {
                            match.path = config.toh.meta.proxy.health.path;
                            route = {
                              cluster = adminClusterName;
                              prefix_rewrite = "/ready";
                            };
                          }
                        ];
                      }
                    ];
                  };
                  http_filters = [
                    {
                      name = "envoy.filters.http.router";
                      typed_config."@type" = "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router";
                    }
                  ];
                };
              }
            ];
          }
        ];
      };

      clusters =
        lib.mapAttrsToList (makeCluster "ROUND_ROBIN") httpServices
        ++ lib.mapAttrsToList (makeCluster "LEAST_REQUEST") tcpServices
        ++ lib.optional (submitServices != [ ]) (makeCluster "LEAST_REQUEST" "submit" submitServices)
        ++ [ adminCluster ];
    in
    {
      options.toh.services.envoy = {
        enable = lib.mkEnableOption "Envoy";

        adminPort = lib.mkOption {
          type = lib.types.port;
          default = 9901;
          description = ''
            Port of the admin interface, on localhost only. It serves the
            stats, and it can also change and stop the proxy.
          '';
        };

        statsPort = lib.mkOption {
          type = lib.types.port;
          default = config.toh.meta.proxy.health.port;
          defaultText = lib.literalExpression "config.toh.meta.proxy.health.port";
          description = ''
            Port that serves only the stats of the admin interface, in the
            format of Prometheus, and the health answer of the proxy, at the
            address of the machine.
          '';
        };

        alerts = {
          deniedPerSecond = lib.mkOption {
            type = lib.types.float;
            default = 1.0;
            description = ''
              Requests a service may turn away per second (status 401 or 403)
              before it is an alert, which can be someone guessing passwords.
            '';
          };

          for = lib.mkOption {
            type = lib.types.str;
            default = "1m";
            description = "How long a service may be down or turn requests away before it is an alert.";
          };
        };

        restartDelay = lib.mkOption {
          type = lib.types.str;
          default = "2s";
          description = "How long systemd waits before it starts a failed proxy again.";
        };

        timeouts = {
          connect = lib.mkOption {
            type = lib.types.str;
            default = "5s";
            description = "How long the proxy waits for a backend to accept a connection.";
          };

          idle = lib.mkOption {
            type = lib.types.str;
            default = "30s";
            description = "How long a request or connection may stay quiet before the proxy ends it.";
          };
        };

        health = {
          interval = lib.mkOption {
            type = lib.types.str;
            default = "2s";
            description = "Time between two health checks of a backend.";
          };

          timeout = lib.mkOption {
            type = lib.types.str;
            default = "2s";
            description = "How long a health check may take before it fails.";
          };

          healthyThreshold = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = "Checks in a row that must pass before a backend gets traffic again.";
          };

          unhealthyThreshold = lib.mkOption {
            type = lib.types.ints.positive;
            default = 3;
            description = "Checks in a row that must fail before a backend loses its traffic.";
          };
        };

        maxRegexSize = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1000;
          description = ''
            Largest compiled size of a route regular expression. Envoy refuses
            to start on a bigger one, and its own limit of 100 is too small
            for the routes of services like the Synapse workers.
          '';
        };

        persistence.ttl = lib.mkOption {
          type = lib.types.str;
          default = "1800s";
          description = ''
            Lifetime of the cookie the proxy sets for a service that persists
            by cookie.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        toh.meta.proxy.enable = true;

        services.envoy = {
          enable = true;
          # NOTE: for now because the envoy package is acting weird
          package = pkgs.envoy-bin;
          # NOTE: the check at build time loads the certificates, which exist
          # only on the machine
          requireValidConfig = false;
          settings = {
            admin.address = socketAddress "127.0.0.1" cfg.adminPort;
            layered_runtime.layers = [
              {
                name = "static";
                static_layer."re2.max_program_size.error_level" = cfg.maxRegexSize;
              }
            ];
            static_resources = {
              listeners = [
                httpsListener
                statsListener
              ]
              ++ tcpListeners
              ++ submitListeners;
              inherit clusters;
            };
          };
        };

        systemd.services.envoy.serviceConfig = {
          LoadCredential = [
            "cert:${config.toh.meta.sops.secrets."envoy-public".path}"
            "key:${config.toh.meta.sops.secrets."envoy-private".path}"
            "ca:${config.toh.meta.sops.secrets."envoy-ca-public".path}"
          ];
          # NOTE: nixpkgs never restarts envoy, and every service of the
          # cluster is behind it
          Restart = lib.mkForce "always";
          RestartSec = cfg.restartDelay;
        };

        networking.firewall.allowedTCPPorts = [
          httpsPort
          submitPort
          cfg.statsPort
        ]
        ++ (builtins.map (serviceName: (proxyAttrs serviceName).port) (builtins.attrNames tcpServices));

        toh.meta.sops.secrets."envoy-ca-public" = {
          key = "openssl-ca-public";
          restartUnits = [ "envoy.service" ];
        };

        toh.meta.sops.secrets."envoy-public".restartUnits = [ "envoy.service" ];

        toh.meta.sops.secrets."envoy-private".restartUnits = [ "envoy.service" ];

        toh.meta.cryl.machine = [
          {
            envoy = {
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
                    config = "envoy-cert-config";
                    request_config = "envoy-cert-request-config";
                    private = "envoy-private";
                    request = "envoy-cert-request";
                    ca_private = "cluster/openssl-ca-private";
                    ca_public = "cluster/openssl-ca-public";
                    serial = "cluster/openssl-ca-serial";
                    public = "envoy-public";
                    renew = true;
                  };
                }
              ];
            };
          }
        ];

        toh.pki.installCa = true;

        toh.meta.metrics.targets.envoy = {
          port = cfg.statsPort;
          path = statsPath;
        };

        toh.meta.metrics.alerts = {
          ServiceDown = {
            expression = ''envoy_cluster_membership_healthy{envoy_cluster_name!="${adminClusterName}"} == 0'';
            inherit (cfg.alerts) for;
            severity = "critical";
            summary = "{{ $labels.envoy_cluster_name }} has no healthy backend as seen from {{ $labels.machine }}";
          };

          RequestsDenied = {
            expression = ''
              sum by (envoy_cluster_name) (
                rate(envoy_cluster_upstream_rq{envoy_response_code=~"401|403"}[5m])
              ) > ${builtins.toString cfg.alerts.deniedPerSecond}
            '';
            inherit (cfg.alerts) for;
            summary = "{{ $labels.envoy_cluster_name }} turns many requests away, someone may be guessing passwords";
          };
        };
      };
    };
}
