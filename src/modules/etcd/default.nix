{
  toh.lib.nixosModules.services-etcd =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.etcd;

      machines = tohLib.serviceMachines "etcd";

      peerPort = 2380;
      peerPortString = builtins.toString peerPort;
      clientPort = cfg.clientPort;
      clientPortString = builtins.toString clientPort;

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.etcd.endpoint;

      initialCluster = builtins.map (
        machine:
        machine.config.toh.meta.machine.name
        + "=https://${machine.config.toh.meta.network.ip}"
        + ":${peerPortString}"
      ) machines;
    in
    {
      options.toh.services = {
        etcd = {
          enable = lib.mkEnableOption "etcd";

          clientPort = lib.mkOption {
            type = lib.types.port;
            default = 2379;
            description = "etcd client port";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.etcd = {
          enable = true;
          name = config.toh.meta.machine.name;
          listenClientUrls = [
            "https://${config.toh.meta.network.ip}:${clientPortString}"
            "https://127.0.0.1:${clientPortString}"
          ];
          advertiseClientUrls = [ "https://${config.toh.meta.network.ip}:${clientPortString}" ];
          listenPeerUrls = [ "https://${config.toh.meta.network.ip}:${peerPortString}" ];
          initialCluster = initialCluster;
          # NOTE: etcd is smart enough to know that it should try joining an existing cluster first
          initialClusterState = "new";
          initialAdvertisePeerUrls = [ "https://${config.toh.meta.network.ip}:${peerPortString}" ];
          initialClusterToken = "toh";

          certFile = config.toh.meta.sops.secrets."etcd-public".path;
          keyFile = config.toh.meta.sops.secrets."etcd-private".path;
          trustedCaFile = config.toh.meta.sops.secrets."etcd-ca-public".path;
          peerCertFile = config.toh.meta.sops.secrets."etcd-public".path;
          peerKeyFile = config.toh.meta.sops.secrets."etcd-private".path;
          peerTrustedCaFile = config.toh.meta.sops.secrets."etcd-ca-public".path;
        };

        # Open ports for client and peer communication
        networking.firewall.allowedTCPPorts = [
          peerPort
          clientPort
        ];

        systemd.services.etcd.wantedBy = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services.etcd.after = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];
        systemd.services.etcd.requires = [
          "toh-network-online.target"
          "toh-time-synchronized.target"
        ];

        systemd.targets.toh-config-online = {
          wantedBy = [ "etcd.service" ];
          bindsTo = [ "etcd.service" ];
          after = [ "etcd.service" ];
        };

        environment.systemPackages = [
          pkgs.etcd
        ];

        programs.rust-motd.settings = {
          service_status = {
            etcd = "etcd";
          };
        };

        toh.meta.services.etcd = {
          endpoint.tcp = {
            port = clientPort;
            layer7Protocol = "https";
            sslTermination = "passthrough";
          };
          health.endpoint.https = {
            port = clientPort;
            path = "health";
          };
        };

        toh.meta.sops.secrets."etcd-ca-public" = {
          key = "openssl-ca-public";
          owner = config.systemd.services.etcd.serviceConfig.User;
          group = config.systemd.services.etcd.serviceConfig.User;
          mode = "0644";
        };
        toh.meta.sops.secrets."etcd-public" = {
          owner = config.systemd.services.etcd.serviceConfig.User;
          group = config.systemd.services.etcd.serviceConfig.User;
          mode = "0644";
        };
        toh.meta.sops.secrets."etcd-private" = {
          owner = config.systemd.services.etcd.serviceConfig.User;
          group = config.systemd.services.etcd.serviceConfig.User;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            etcd = {
              generations = [
                {
                  generator = "tls-leaf";
                  arguments = {
                    common_name = "toh";
                    organization = "ToH";
                    sans = [
                      proxyAttrs.host
                      config.toh.meta.network.ip
                      "localhost"
                      "127.0.0.1"
                    ];
                    config = "etcd-cert-config";
                    request_config = "etcd-cert-request-config";
                    private = "etcd-private";
                    request = "etcd-cert-request";
                    ca_private = "cluster/openssl-ca-private";
                    ca_public = "cluster/openssl-ca-public";
                    serial = "cluster/openssl-ca-serial";
                    public = "etcd-public";
                    renew = true;
                  };
                }
              ];
            };
          }
        ];

        toh.pki.generateCa = true;
      };
    };
}
