{ selfLib, ... }:

{
  self.nixosModules.services-synapse-worker.flake = true;
  self.nixosModules.services-synapse-worker.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.synapse;

      synapseCfg = config.services.matrix-synapse;
      mainUnit = config.systemd.services.matrix-synapse;

      replicationAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.synapse-replication.endpoint;

      serviceDependencies = [
        "synapse-config.service"
        "toh-database-online.target"
        "toh-kv-online.target"
      ];

      # NOTE: the paths the Synapse docs list for a generic worker, as
      # regular expressions for the whole path; logins, pagination, media
      # and inbound federation transactions stay on the main process
      clientPaths = [
        "/_matrix/client/(r0|v3)/sync"
        "/_matrix/client/(api/v1|r0|v3)/(events|initialSync)"
        "/_matrix/client/(api/v1|r0|v3)/rooms/[^/]+/initialSync"
        "/_matrix/client/versions"
        "/_matrix/client/(r0|v3|unstable)/(account/whoami|capabilities)"
        "/_matrix/client/(api/v1|r0|v3|unstable)/joined_rooms"
        "/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/(joined_members|members|state|state/.*|context/.*|event/.*)"
        "/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/(send|redact)(/.*)?"
        "/_matrix/client/(api/v1|r0|v3|unstable)/rooms/.*/(join|invite|leave|ban|unban|kick)"
        "/_matrix/client/(api/v1|r0|v3|unstable)/(join|knock|profile)/.*"
        "/_matrix/client/(api/v1|r0|v3|unstable)/directory/room/.*"
        "/_matrix/client/(r0|v3|unstable)/keys/(query|changes|claim)"
      ];

      federationPaths = [
        "/_matrix/federation/v1/version"
        "/_matrix/federation/v1/(event|state|state_ids|backfill|get_missing_events|query|make_join|make_leave|make_knock|send_knock|event_auth|timestamp_to_event|exchange_third_party_invite|user/devices|hierarchy)/.*"
        "/_matrix/federation/v1/publicRooms.*"
        "/_matrix/federation/(v1|v2)/(send_join|send_leave|invite)/.*"
        "/_matrix/key/v2/query.*"
      ];

      workerConfigFile = (pkgs.formats.yaml { }).generate "synapse-worker.yaml" {
        worker_app = "synapse.app.generic_worker";
        worker_name = "worker-${config.toh.meta.machine.name}";
        worker_log_config = synapseCfg.settings.log_config;
        worker_listeners = [
          {
            type = "http";
            port = cfg.worker.port;
            bind_addresses = [ config.toh.meta.network.ip ];
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
        # NOTE: the main process keeps the media, see the design
        enable_media_repo = false;
        # NOTE: the main process moves with the lease, so the worker reaches
        # it at its proxy address and not on a machine
        instance_map.main = {
          host = replicationAttrs.host;
          port = replicationAttrs.port;
          tls = true;
        };
      };

      configPaths = [
        synapseCfg.configFile
        workerConfigFile
      ]
      ++ synapseCfg.extraConfigFiles;
    in
    {
      options.toh.services.synapse.worker = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8092;
          description = "Port of the HTTP listener of the worker.";
        };

        restartSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = ''
            Seconds between starts of the worker, which fails until the main
            process has set up the database.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # NOTE: our own unit and not a worker of the nixpkgs module, because
        # those need the main process on the same machine; it runs with the
        # allocator and the hardening of the main process
        systemd.services.matrix-synapse-worker = {
          description = "Synapse worker";
          wantedBy = [ "multi-user.target" ];
          after = serviceDependencies;
          requires = serviceDependencies;
          inherit (mainUnit) environment;
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig = mainUnit.serviceConfig // {
            ExecStart =
              "${synapseCfg.package}/bin/synapse_worker"
              + lib.concatMapStrings (path: " --config-path ${path}") configPaths
              + " --keys-directory ${synapseCfg.dataDir}";
            RestartSec = cfg.worker.restartSeconds;
          };
        };

        networking.firewall.allowedTCPPorts = [ cfg.worker.port ];

        toh.meta.services.synapse-worker = {
          endpoint.http = {
            port = cfg.worker.port;
            route = {
              service = "synapse";
              paths = builtins.map (regex: { inherit regex; }) (clientPaths ++ federationPaths);
            };
          };
          health.endpoint.http = {
            port = cfg.worker.port;
            path = "/health";
          };
        };
      };
    };
}
