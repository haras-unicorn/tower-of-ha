# NOTE: the config of the redis module is the same on every start, so before a
# server or a sentinel starts, primary.nu points it at the primary the other
# sentinels agree on; the bootstrap primary only counts on the very first start
# of a machine, while no sentinel answers

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

      otherMachines = builtins.filter (
        machine: machine.name != config.toh.meta.machine.name
      ) valkeyMachines;

      # NOTE: the paths the redis module keeps the config of each server in,
      # which Valkey rewrites when a sentinel reconfigures it
      serverConf = "/var/lib/redis-valkey/redis.conf";
      sentinelConf = "/var/lib/redis-valkey-sentinel/redis.conf";

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

          sentinel.askTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = ''
              Seconds a machine waits for each of the other sentinels to name
              the primary before its server or sentinel starts.
            '';
          };

          sentinel.failoverTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 60000;
            description = ''
              Milliseconds a sentinel gives a failover to finish. A sentinel
              that took part in a failover starts no other failover of the
              same primary for twice this long, so it is also how soon the
              cluster survives the loss of the next primary.
            '';
          };

          minReplicasToWrite = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = if builtins.length valkeyMachines > 1 then 1 else 0;
            defaultText = lib.literalMD "1, or 0 when only one machine runs Valkey";
            description = ''
              Replicas that have to keep up with the primary for it to take
              writes (`min-replicas-to-write`). Valkey replicates after it
              answers, so this does not make a write wait for a replica; it
              only makes the primary refuse writes once fewer replicas than
              this acknowledged within `replicaMaxLag`, which bounds how much
              a failover can lose. 0 never refuses.
            '';
          };

          replicaMaxLag = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = ''
              Seconds since its last acknowledgement after which a replica no
              longer counts for `minReplicasToWrite`
              (`min-replicas-max-lag`). The writes of about this many seconds
              can be lost with the primary. Replicas acknowledge every second,
              so 1 would refuse writes on every late acknowledgement.
            '';
          };
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
                  min-replicas-to-write = cfg.minReplicasToWrite;
                  min-replicas-max-lag = cfg.replicaMaxLag;
                  aclfile = config.toh.meta.sops.secrets."valkey-acl".path;
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

          toh.overlays = selfLib.cli.makeOverlays {
            name = "valkey-primary";
            runtimeInputs = (
              pkgs: [
                pkgs.valkey
                pkgs.coreutils
              ]
            );
            textFile = ./primary.nu;
            textVariables = {
              TOH_VALKEY_PRIMARY_NAME = bootstrapPrimaryName;
              TOH_VALKEY_PRIMARY_OWN_IP = config.toh.meta.network.ip;
              TOH_VALKEY_PRIMARY_BOOTSTRAP_IP = bootstrapPrimaryIp;
              TOH_VALKEY_PRIMARY_PORT = builtins.toString valkeyPort;
              TOH_VALKEY_PRIMARY_SENTINEL_PORT = builtins.toString sentinelPort;
              TOH_VALKEY_PRIMARY_SENTINELS = builtins.toJSON (
                builtins.map (machine: machine.meta.network.ip) otherMachines
              );
              TOH_VALKEY_PRIMARY_USER = selfLib.valkey.users.sentinel;
              TOH_VALKEY_PRIMARY_PASSWORD = sentinel.password;
              TOH_VALKEY_PRIMARY_CA = sentinel.ca;
              TOH_VALKEY_PRIMARY_SERVER_CONF = serverConf;
              TOH_VALKEY_PRIMARY_SENTINEL_CONF = sentinelConf;
              TOH_VALKEY_PRIMARY_BOOTSTRAPPED = "/var/lib/redis-valkey/toh-bootstrapped";
              TOH_VALKEY_PRIMARY_TIMEOUT = builtins.toString cfg.sentinel.askTimeout;
            };
          };

          systemd.services.redis-valkey.serviceConfig.ExecStartPre = lib.mkAfter [
            "+${pkgs.tohPackages.valkey-primary}/bin/valkey-primary server"
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
          # the same reason as the module, replace-secret; the module has no
          # option for the failover timeout either, so it goes in here too
          systemd.services.redis-valkey-sentinel.serviceConfig.ExecStartPre = lib.mkAfter [
            (
              "+"
              + pkgs.writeShellScript "redis-valkey-sentinel-user" ''
                conf=/run/redis-valkey-sentinel/nixos.conf
                echo "sentinel failover-timeout ${bootstrapPrimaryName} ${builtins.toString cfg.sentinel.failoverTimeout}" >> "$conf"
                echo "sentinel sentinel-user ${selfLib.valkey.users.sentinel}" >> "$conf"
                echo "sentinel sentinel-pass @SENTINEL_PASS@" >> "$conf"
                ${lib.getExe pkgs.replace-secret} '@SENTINEL_PASS@' ${lib.escapeShellArg sentinel.password} "$conf"
              ''
            )
            "+${pkgs.tohPackages.valkey-primary}/bin/valkey-primary sentinel"
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
