# TODO: security

{
  toh.lib.nixosModules.services-seaweedfs =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      machines = tohLib.serviceMachines "seaweedfs";

      peers = builtins.map (
        machine:
        let
          masterCfg = machine.config.services.seaweedfs.master;
          ip = masterCfg.ip;
          port = masterCfg.httpPort;
        in
        "${ip}:${builtins.toString port}"
      ) (builtins.filter (machine: machine.name != config.toh.meta.machine.name) machines);

      masters = builtins.map (
        machine:
        let
          masterCfg = machine.config.services.seaweedfs.master;
          ip = masterCfg.ip;
          port = masterCfg.httpPort;
        in
        "${ip}:${builtins.toString port}"
      ) machines;
    in
    {
      options.toh.services = {
        seaweedfs = {
          enable = lib.mkEnableOption "SeaweedFS";
        };
      };

      config = lib.mkIf config.toh.services.seaweedfs.enable {
        services.seaweedfs.master.enable = true;
        services.seaweedfs.master.openFirewall = true;
        services.seaweedfs.master.ip = config.toh.meta.network.ip;
        services.seaweedfs.master.peers = peers;
        systemd.services."seaweedfs-master".wantedBy = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services."seaweedfs-master".requires = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services."seaweedfs-master".after = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];

        services.seaweedfs.volumes.toh.enable = true;
        # TODO: remove mention of cockroachdb here
        # NOTE: 8080 is cockroachdb
        services.seaweedfs.volumes.toh.httpPort = 8081;
        services.seaweedfs.volumes.toh.ip = config.toh.meta.network.ip;
        services.seaweedfs.volumes.toh.masterServers = masters;
        services.seaweedfs.volumes.toh.openFirewall = true;
        services.seaweedfs.volumes.toh.dataCenter = config.toh.locality.dataCenter;
        services.seaweedfs.volumes.toh.rack = config.toh.locality.rack;
        systemd.services."seaweedfs-volume@toh".wantedBy = [ "seaweedfs-master.service" ];
        systemd.services."seaweedfs-volume@toh".requires = [ "seaweedfs-master.service" ];
        systemd.services."seaweedfs-volume@toh".after = [ "seaweedfs-master.service" ];

        services.seaweedfs.filers.toh.enable = true;
        services.seaweedfs.filers.toh.ip = config.toh.meta.network.ip;
        services.seaweedfs.filers.toh.masterServers = masters;
        services.seaweedfs.filers.toh.openFirewall = true;
        services.seaweedfs.filers.toh.environmentFile = config.sops.secrets."seaweedfs-filer-env".path;
        services.seaweedfs.filers.toh.dataCenter = config.toh.locality.dataCenter;
        services.seaweedfs.filers.toh.rack = config.toh.locality.rack;
        # TODO: remove mention of postgres here
        # TODO: ssl certs like this
        # sslmode = "verify-full"
        # sslcert = "/path/to/client.crt"
        # sslkey = "/path/to/client.key"
        # sslrootcert = "/path/to/ca.crt"
        services.seaweedfs.filers.toh.config.postgres = {
          enabled = true;
          hostname = config.toh.meta.database.host;
          port = config.toh.meta.database.port;
          username = config.toh.meta.database.instances.seaweedfs.user;
          database = config.toh.meta.database.instances.seaweedfs.name;
        };
        systemd.services."seaweedfs-filer@toh".wantedBy = [
          "seaweedfs-master.service"
          "toh-database-initialized.target"
        ];
        systemd.services."seaweedfs-filer@toh".requires = [
          "seaweedfs-master.service"
          "toh-database-initialized.target"
        ];
        systemd.services."seaweedfs-filer@toh".after = [
          "seaweedfs-master.service"
          "toh-database-initialized.target"
        ];

        systemd.targets.toh-filesystem-initialized = {
          wantedBy = [
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
          bindsTo = [
            "seaweedfs-initialization.service"
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
          after = [
            "seaweedfs-initialization.service"
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
        };
        systemd.services.seaweedfs-initialization = {
          description = "SeaweedFS initialization";
          wantedBy = [
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
          bindsTo = [
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
          after = [
            "seaweedfs-master.service"
            "seaweedfs-volume@toh.service"
            "seaweedfs-filer@toh.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
            ExecStart =
              let
                ip = config.toh.meta.network.ip;
                masterPort = builtins.toString config.services.seaweedfs.master.httpPort;
                volumePort = builtins.toString config.services.seaweedfs.volumes.toh.httpPort;
                filerPort = builtins.toString config.services.seaweedfs.filers.toh.httpPort;

                maxRetries = 10;
                timeoutSec = 30;
                initialBackoff = 2;

                script = pkgs.writeShellApplication {
                  name = "seaweedfs-initialization";
                  runtimeInputs = [ pkgs.curl ];
                  text = ''
                    check_endpoint() {
                      local port="$1"
                      local path="$2"
                      local attempt=0
                      local backoff=${toString initialBackoff}

                      while [ $attempt -lt ${builtins.toString maxRetries} ]; do
                        if curl \
                          -fs \
                          --max-time ${builtins.toString timeoutSec} \
                          "http://${ip}:$port$path"; then
                          return 0
                        fi
                        sleep $backoff
                        attempt=$((attempt + 1))
                        backoff=$((backoff * 2))
                      done
                      return 1
                    }

                    check_endpoint ${masterPort} "/cluster/healthz" && \
                    check_endpoint ${volumePort} "/healthz" && \
                    check_endpoint ${filerPort} "/healthz" || \
                    exit 1
                  '';
                };
              in
              lib.getExe script;
          };
        };

        environment.systemPackages = [
          pkgs.seaweedfs
        ];

        # NOTE: something is needed just so the mounts work properly
        users.users.seaweedfs.uid = 18888;
        users.groups.seaweedfs.gid = 18888;

        toh.meta.services = [
          {
            name = "seaweedfs-master";
            port = config.services.seaweedfs.master.httpPort;
            health = "http://";
          }
          {
            name = "seaweedfs-volume";
            port = config.services.seaweedfs.volumes.toh.httpPort;
            health = "http:///status";
          }
          {
            name = "seaweedfs-filer";
            port = config.services.seaweedfs.filers.toh.httpPort;
            health = "http://";
          }
        ];

        sops.secrets."seaweedfs-filer-env" = {
          owner = config.services.seaweedfs.filers.toh.user;
          group = config.services.seaweedfs.filers.toh.group;
          mode = "0400";
        };

        toh.meta.database.apps.seaweedfs = {
          user = config.services.seaweedfs.filers.toh.user;
          group = config.services.seaweedfs.filers.toh.group;
          init.sql.script = ''
            create table if not exists filemeta (
              dirhash     bigint,
              name        varchar(65535),
              directory   varchar(65535),
              meta        bytea,
              primary key (dirhash, name)
            );
          '';
          secrets.generations = [
            {
              generator = "text";
              arguments = {
                name = "seaweedfs-filer-secret-path";
                # TODO: remove mention of postgres here
                text = config.toh.meta.database.instances.seaweedfs.passwordSecret;
              };
            }
            {
              generator = "env";
              arguments = {
                name = "seaweedfs-filer-env";
                renew = true;
                variables = {
                  type = "map";
                  value = {
                    WEED_POSTGRES_PASSWORD = "seaweedfs-filer-secret-path";
                  };
                };
              };
            }
          ];
        };
      };
    };
}
