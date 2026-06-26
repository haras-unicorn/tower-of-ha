# TODO: make configuration store configurable

{
  toh.lib.nixosModules.services-patroni =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.patroni;

      anyMachines = tohLib.anyServiceMachines "patroni";

      subnetAttrs = config.toh.meta.network.subnet;
      subnetCidr = "${subnetAttrs.ip}/${builtins.toString subnetAttrs.bits}";

      postgresPort = 5432;
      patroniPort = 8008;

      etcdProxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.etcd.endpoint;
      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.postgresql.endpoint;

      owner = config.systemd.services.patroni.serviceConfig.User;
      group = config.systemd.services.patroni.serviceConfig.Group;
    in
    {
      options.toh.services = {
        patroni = {
          enable = lib.mkEnableOption "Patroni";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.database = {
            protocol = "postgresql";
            host = proxyAttrs.host;
            port = proxyAttrs.port;
          };
        })
        (lib.mkIf cfg.enable {
          services.patroni = {
            enable = true;
            postgresqlPackage = pkgs.postgresql_18;
            scope = "toh";
            name = config.toh.meta.machine.name;
            namespace = "/toh/patroni";
            nodeIp = config.toh.meta.network.ip;
            softwareWatchdog = true;
            postgresqlPort = postgresPort;
            restApiPort = patroniPort;
            settings = {
              bootstrap = {
                dcs = { };
                initdb = [
                  "encoding=UTF8"
                  "data-checksums"
                ];
              };

              log = {
                deduplicate_heartbeat_logs = true;
              };

              etcd3 = {
                host = "${etcdProxyAttrs.host}:${builtins.toString etcdProxyAttrs.port}";
                protocol = etcdProxyAttrs.protocol;
                cacert = config.toh.meta.sops.secrets."patroni-etcd-ca".path;
                cert = config.toh.meta.sops.secrets."patroni-etcd-public".path;
                key = config.toh.meta.sops.secrets."patroni-etcd-private".path;
              };

              restapi = {
                certfile = config.toh.meta.sops.secrets."patroni-restapi-public".path;
                keyfile = config.toh.meta.sops.secrets."patroni-restapi-private".path;
              };

              postgresql = {
                pg_hba =
                  let
                    makeSuperuserAcl =
                      user: withReplication:
                      [
                        "hostssl all ${user} 127.0.0.1/32 cert"
                        "host all ${user} 127.0.0.1/32 scram-sha-256"
                        "local all ${user} scram-sha-256"
                        "hostnossl all ${user} ${subnetCidr} reject"
                        "hostssl all ${user} ${subnetCidr} cert"
                      ]
                      ++ lib.optionals withReplication [
                        "hostssl replication ${user} 127.0.0.1/32 cert"
                        "local replication ${user} 127.0.0.1/32 scram-sha-256"
                        "local replication ${user} scram-sha-256"
                        "hostnossl replication ${user} ${subnetCidr} reject"
                        "hostssl replication ${user} ${subnetCidr} cert"
                      ];

                    makeSubnetAclForDatabaseAndUser = database: user: [
                      "hostnossl ${database} ${user} ${subnetCidr} reject"
                      "hostssl ${database} ${user} ${subnetCidr} scram-sha-256"
                    ];
                  in
                  makeSuperuserAcl tohLib.patroni.superusers.superuser false
                  ++ makeSuperuserAcl tohLib.patroni.superusers.replication true
                  ++ makeSuperuserAcl tohLib.patroni.superusers.rewind false
                  ++ makeSubnetAclForDatabaseAndUser "all" "all";

                parameters = {
                  ssl = "on";
                  ssl_cert_file = config.toh.meta.sops.secrets."patroni-ssl-public".path;
                  ssl_key_file = config.toh.meta.sops.secrets."patroni-ssl-private".path;
                  ssl_ca_file = config.toh.meta.sops.secrets."patroni-ssl-ca".path;
                  log_line_prefix = "%m [%p] %a ";
                };

                authentication = builtins.listToAttrs (
                  lib.mapAttrsToList (name: user: {
                    inherit name;
                    value = {
                      username = user;
                      password = "file://${config.toh.services.patroni.users.${user}.password}";
                      sslmode = "verify-full";
                      sslcert = config.toh.services.patroni.users.${user}.crt;
                      sslkey = config.toh.services.patroni.users.${user}.key;
                      sslrootcert = config.toh.services.patroni.users.${user}.ca;
                    };
                  }) tohLib.patroni.superusers
                );
              };
            };
          };

          # NOTE: for the socket and proper permissions
          systemd.tmpfiles.rules = [
            "d /run/postgresql 0755 patroni patroni -"
          ];

          networking.firewall.allowedTCPPorts = [
            postgresPort
            patroniPort
          ];

          systemd.services.patroni.wantedBy = [
            "toh-config-online.target"
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.patroni.after = [
            "toh-config-online.target"
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.patroni.requires = [
            "toh-config-online.target"
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];

          systemd.targets.toh-database-online = {
            wantedBy = [ "patroni.service" ];
            bindsTo = [ "patroni.service" ];
            after = [ "patroni.service" ];
          };

          programs.rust-motd.settings.service_status.Patroni = "patroni";

          toh.meta.services.patroni = {
            endpoint.https = {
              port = patroniPort;
            };
            health.endpoint.https = {
              port = patroniPort;
              path = "health";
            };
          };

          toh.meta.services.postgresql = {
            endpoint.tcp = {
              port = postgresPort;
              layer7Protocol = "postgresql";
              sslTermination = "passthrough";
            };
            health.endpoint.https = {
              port = patroniPort;
              path = "read-write";
            };
          };

          toh.meta.sops.secrets."patroni-etcd-ca" = {
            inherit owner group;
            key = "openssl-ca-public";
            mode = "0644";
          };
          toh.meta.sops.secrets."patroni-etcd-public" = {
            inherit owner group;
            mode = "0644";
          };
          toh.meta.sops.secrets."patroni-etcd-private" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."patroni-restapi-public" = {
            inherit owner group;
            mode = "0644";
          };
          toh.meta.sops.secrets."patroni-restapi-private" = {
            inherit owner group;
            mode = "0400";
          };
          toh.meta.sops.secrets."patroni-ssl-ca" = {
            key = "openssl-ca-public";
            inherit owner group;
            mode = "0644";
          };
          toh.meta.sops.secrets."patroni-ssl-public" = {
            inherit owner group;
            mode = "0644";
          };
          toh.meta.sops.secrets."patroni-ssl-private" = {
            inherit owner group;
            mode = "0400";
          };

          toh.meta.cryl.machine = [
            {
              patroni = {
                generations = [
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = proxyAttrs.host;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "patroni-etcd-cert-config";
                      request_config = "patroni-etcd-cert-request-config";
                      private = "patroni-etcd-private";
                      request = "patroni-etcd-cert-request";
                      ca_private = "cluster/openssl-ca-private";
                      ca_public = "cluster/openssl-ca-public";
                      serial = "cluster/openssl-ca-serial";
                      public = "patroni-etcd-public";
                      renew = true;
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = proxyAttrs.host;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "patroni-restapi-cert-config";
                      request_config = "patroni-restapi-cert-request-config";
                      private = "patroni-restapi-private";
                      request = "patroni-restapi-cert-request";
                      ca_private = "cluster/openssl-ca-private";
                      ca_public = "cluster/openssl-ca-public";
                      serial = "cluster/openssl-ca-serial";
                      public = "patroni-restapi-public";
                      renew = true;
                    };
                  }
                  {
                    generator = "tls-leaf";
                    arguments = {
                      common_name = proxyAttrs.host;
                      organization = "ToH";
                      sans = [
                        proxyAttrs.host
                        config.toh.meta.network.ip
                        "localhost"
                        "127.0.0.1"
                      ];
                      config = "patroni-ssl-cert-config";
                      request_config = "patroni-ssl-cert-request-config";
                      private = "patroni-ssl-private";
                      request = "patroni-ssl-cert-request";
                      ca_private = "cluster/openssl-ca-private";
                      ca_public = "cluster/openssl-ca-public";
                      serial = "cluster/openssl-ca-serial";
                      public = "patroni-ssl-public";
                      renew = true;
                    };
                  }
                ];
              };
            }
          ];

          toh.services.patroni.users = builtins.listToAttrs (
            builtins.map (name: {
              inherit name;
              value.installSecrets = true;
            }) (builtins.attrValues tohLib.patroni.superusers)
          );

          toh.pki.generateCa = true;
        })
      ];
    };
}
