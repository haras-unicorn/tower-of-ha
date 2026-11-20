{ selfLib, ... }:

{
  self.nixosModules.services-synapse.flake = true;
  self.nixosModules.services-synapse.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.synapse;

      anyMachines = selfLib.cluster.anyServiceMachines config "synapse";

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.synapse.endpoint;

      serviceTargets = [
        "toh-database-online.target"
        "toh-filesystem-online.target"
      ];
      serviceDependencies = [ "synapse-config.service" ] ++ serviceTargets;
    in
    {
      options.toh.services = {
        synapse = {
          enable = lib.mkEnableOption "Matrix Synapse";

          port = lib.mkOption {
            type = lib.types.port;
            # NOTE: not the 8008 Synapse uses by default, Patroni has it
            default = 8090;
            description = "Port of the HTTP listener of the main process.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.chat = {
            host = proxyAttrs.host;
            port = proxyAttrs.port;
          };
        })
        (lib.mkIf cfg.enable {
          services.matrix-synapse = {
            enable = true;
            withJemalloc = true;

            extraConfigFiles = [ cfg.config.path ];

            settings = {
              server_name = proxyAttrs.host;
              public_baseurl = "https://${proxyAttrs.host}";

              enable_registration = false;
              report_stats = false;

              signing_key_path = cfg.config.signingKeyPath;
              media_store_path = cfg.media.path;

              listeners = [
                {
                  port = cfg.port;
                  bind_addresses = [ config.toh.meta.network.ip ];
                  type = "http";
                  tls = false;
                  x_forwarded = true;
                  resources = [
                    {
                      names = [
                        "client"
                        "federation"
                      ];
                      compress = false;
                    }
                  ];
                }
              ];
            };
          };

          # NOTE: only one main process may run, and it keeps its data in
          # the database and on CephFS, so the machine that holds the lease
          # runs it and the others take over when that machine stops
          toh.leases.synapse.services = [ "matrix-synapse" ];

          systemd.services.matrix-synapse = {
            after = serviceDependencies;
            requires = serviceDependencies;
          };

          systemd.targets.toh-chat-online = {
            wantedBy = [ "toh-lease-synapse.service" ];
            after = [ "toh-lease-synapse.service" ];
            requires = [ "toh-lease-synapse.service" ];
          };

          networking.firewall.allowedTCPPorts = [ cfg.port ];

          toh.meta.services.synapse = {
            endpoint.http = {
              port = cfg.port;
            };
            health.endpoint.http = {
              port = cfg.port;
              path = "/health";
            };
          };

          toh.services.synapse.createUserGroup = true;
        })
      ];
    };
}
