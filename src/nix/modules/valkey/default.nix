# TODO: replace static bootstrapPrimary with post-start script that discovers
# the current primary via sentinel and adjusts replication accordingly.
# This would eliminate the need for a pre-designated bootstrap node.

{ selfLib, ... }:

{
  self.nixosModules.services-valkey.flake = true;
  self.nixosModules.services-valkey.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.valkey;

      anyMachines = selfLib.cluster.anyServiceMachines config "valkey";
      valkeyMachines = selfLib.cluster.serviceMachines config "valkey";

      valkeyPort = 6379;
      sentinelPort = 26379;

      bootstrapPrimary = lib.head valkeyMachines;
      bootstrapPrimaryIp = bootstrapPrimary.meta.network.ip;
      bootstrapPrimaryName = bootstrapPrimary.name;
      isBootstrapPrimary = config.toh.meta.machine.name == bootstrapPrimaryName;

      quorum = lib.trivial.min (builtins.ceil ((builtins.length valkeyMachines) / 2.0)) (
        builtins.length valkeyMachines
      );

      proxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.valkey.endpoint;

      valkeyUser = "valkey";
      valkeyGroup = "valkey";

      master = config.toh.services.valkey.users.${selfLib.valkey.users.master};
      sentinel = config.toh.services.valkey.users.${selfLib.valkey.users.sentinel};

      # NOTE: reasoning is that i could use the same database as the app ports
      # since those are cluster-wide unique per-app but shared per-app per-host
      maxDatabases = 65535;
    in
    {
      options.toh.services = {
        valkey = {
          enable = lib.mkEnableOption "Valkey";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.kv = {
            protocol = "rediss";
            host = proxyAttrs.host;
            port = proxyAttrs.port;
          };
        })
        (lib.mkIf cfg.enable {
          services.redis = {
            package = pkgs.valkey;

            vmOverCommit = true;

            servers = {
              valkey = {
                enable = true;
                user = valkeyUser;
                group = valkeyGroup;
                # NOTE: only tls enabled
                port = 0;
                bind = config.toh.meta.network.ip;
                databases = maxDatabases;
                masterAuthFile = master.password;
                masterUser = selfLib.valkey.users.master;
                settings = {
                  protected-mode = false;
                  tls-port = valkeyPort;
                  tls-cert-file = master.crt;
                  tls-key-file = master.key;
                  tls-ca-cert-file = master.ca;
                  tls-auth-clients = false;
                  tls-replication = true;
                  replica-serve-stale-data = false;
                  aclfile = config.toh.meta.sops.secrets."valkey-acl".path;
                  replicaof = lib.mkIf (!isBootstrapPrimary) "${bootstrapPrimaryIp} ${builtins.toString valkeyPort}";
                };
              };

              valkey-sentinel = {
                enable = true;
                user = valkeyUser;
                group = valkeyGroup;
                # NOTE: only tls enabled
                port = 0;
                bind = config.toh.meta.network.ip;
                databases = maxDatabases;
                extraParams = [ "--sentinel" ];
                sentinelMasterHost = bootstrapPrimaryIp;
                sentinelMasterName = bootstrapPrimaryName;
                sentinelMasterPort = valkeyPort;
                sentinelMasterQuorum = quorum;
                sentinelAuthPassFile = sentinel.password;
                sentinelAuthUser = selfLib.valkey.users.sentinel;
                save = [ ];
                settings = {
                  protected-mode = false;
                  tls-port = sentinelPort;
                  tls-cert-file = sentinel.crt;
                  tls-key-file = sentinel.key;
                  tls-ca-cert-file = sentinel.ca;
                  tls-auth-clients = false;
                  tls-replication = true;
                  aclfile = config.toh.meta.sops.secrets."valkey-acl".path;
                };
              };
            };
          };

          networking.firewall.allowedTCPPorts = [
            valkeyPort
            sentinelPort
          ];

          systemd.services.redis-valkey = {
            wantedBy = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
            after = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
            requires = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
            ];
          };

          # NOTE: sentinels ask each other whether the primary is down, and
          # the default user of the ACL may only ping, so without a user of
          # their own they never agree and never fail over; the redis module
          # has no option for that user, so this adds it to the runtime config
          # the way the module adds the password of the primary, in shell for
          # the same reason as the module, replace-secret
          systemd.services.redis-valkey-sentinel.serviceConfig.ExecStartPre = lib.mkAfter [
            (
              "+"
              + pkgs.writeShellScript "redis-valkey-sentinel-user" ''
                conf=/run/redis-valkey-sentinel/nixos.conf
                echo "sentinel sentinel-user ${selfLib.valkey.users.sentinel}" >> "$conf"
                echo "sentinel sentinel-pass @SENTINEL_PASS@" >> "$conf"
                ${lib.getExe pkgs.replace-secret} '@SENTINEL_PASS@' ${lib.escapeShellArg sentinel.password} "$conf"
              ''
            )
          ];

          systemd.services.redis-valkey-sentinel = {
            wantedBy = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
              "redis-valkey.service"
            ];
            after = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
              "redis-valkey.service"
            ];
            requires = [
              "toh-network-online.target"
              "toh-time-synchronized.target"
              "redis-valkey.service"
            ];
          };

          systemd.targets.toh-kv-online = {
            wantedBy = [
              "redis-valkey.service"
              "redis-valkey-sentinel.service"
            ];
            bindsTo = [
              "redis-valkey.service"
              "redis-valkey-sentinel.service"
            ];
            after = [
              "redis-valkey.service"
              "redis-valkey-sentinel.service"
            ];
          };

          programs.rust-motd.settings.service_status.Valkey = "redis-valkey";

          toh.meta.services.valkey = {
            endpoint.tcp = {
              port = valkeyPort;
              layer7Protocol = "redis";
              sslTermination = "passthrough";
            };
            health.endpoint.tcp = {
              port = valkeyPort;
              ssl = true;
              packets = [
                {
                  send = "PING\r\n";
                  expect = "+PONG";
                }
                {
                  send = "info replication\r\n";
                  expect = "role:master";
                }
                {
                  send = "QUIT\r\n";
                  expect = "+OK";
                }
              ];
            };
          };

          toh.services.valkey.users.${selfLib.valkey.users.master} = {
            user = valkeyUser;
            group = valkeyGroup;
            installSecrets = true;
            prefix = "all";
            database = "all";
            permissions = [ selfLib.kv.permissions.all ];
          };

          toh.services.valkey.users.${selfLib.valkey.users.sentinel} = {
            user = valkeyUser;
            group = valkeyGroup;
            installSecrets = true;
            prefix = "all";
            database = "all";
            permissions = [ selfLib.kv.permissions.all ];
          };

          toh.services.valkey.users.${selfLib.valkey.users.superuser} = {
            user = valkeyUser;
            group = valkeyGroup;
            installSecrets = true;
            prefix = "all";
            database = "all";
            permissions = [ selfLib.kv.permissions.all ];
          };

          toh.services.valkey.users.${selfLib.valkey.users.default} = {
            user = valkeyUser;
            group = valkeyGroup;
            generateSecrets = true;
            prefix = "none";
            database = "none";
            permissions = [ selfLib.kv.permissions.health ];
            password = null;
          };

          toh.services.valkey.createUserGroup = true;

          toh.pki.installCa = true;
        })
      ];
    };
}
