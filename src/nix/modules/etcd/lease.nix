{ selfLib, ... }:

{
  self.nixosModules.services-etcd-lease.flake = true;
  self.nixosModules.services-etcd-lease.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      leases = config.toh.leases;

      etcdUrl = selfLib.services.endpoint.toUrl config.toh.meta.proxies.etcd.endpoint { };

      caSecret = "lease-etcd-ca";
      publicSecret = "lease-etcd-public";
      privateSecret = "lease-etcd-private";

      secretPath = name: config.toh.meta.sops.secrets.${name}.path;

      leaseService = name: "toh-lease-${name}";
    in
    {
      options.toh.leases = lib.mkOption {
        default = { };
        description = ''
          Services that may run on only one machine at a time. Every machine
          campaigns for an etcd lock, and the one that holds it runs the
          services. When it stops or loses etcd, the lock runs out and another
          machine takes over.
        '';
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                services = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = ''
                    Systemd services, without `.service`, that run only on the
                    machine holding the lease.
                  '';
                };

                key = lib.mkOption {
                  type = lib.types.str;
                  default = "toh/lease/${name}";
                  description = "The etcd key of the lock.";
                };

                ttl = lib.mkOption {
                  type = lib.types.ints.positive;
                  default = 10;
                  description = ''
                    Seconds until a lost holder's lock runs out, so also about
                    how long a failover takes.
                  '';
                };
              };
            }
          )
        );
      };

      config = lib.mkIf (leases != { }) {
        systemd.services = lib.mkMerge (
          lib.mapAttrsToList (name: lease: {
            ${leaseService name} = {
              description = "Hold the '${name}' lease and run its services";
              wantedBy = [ "multi-user.target" ];
              wants = [ "toh-config-online.target" ];
              after = [ "toh-config-online.target" ];
              path = [
                pkgs.etcd
                config.systemd.package
              ];
              # NOTE: etcdctl prints the lock key once it holds the lock and
              # then waits until it is stopped or the lock runs out; the trap
              # keeps the shell alive until etcdctl has released the lock and
              # exited, because in containers systemd does not notice when
              # the last process of a unit exits after its main process
              script = ''
                trap true TERM
                etcdctl \
                  --endpoints=${etcdUrl} \
                  --cacert=${secretPath caSecret} \
                  --cert=${secretPath publicSecret} \
                  --key=${secretPath privateSecret} \
                  lock --ttl=${builtins.toString lease.ttl} ${lease.key} \
                  | {
                    read -r _
                    systemctl start --no-block ${
                      builtins.concatStringsSep " " (builtins.map (service: "${service}.service") lease.services)
                    }
                    cat >/dev/null
                  }
              '';
              startLimitIntervalSec = 0;
              serviceConfig = {
                Restart = "always";
                RestartSec = lease.ttl;
              };
            };
          }) leases
          ++ lib.concatLists (
            lib.mapAttrsToList (
              name: lease:
              builtins.map (service: {
                ${service} = {
                  wantedBy = lib.mkForce [ ];
                  bindsTo = [ "${leaseService name}.service" ];
                  after = [ "${leaseService name}.service" ];
                };
              }) lease.services
            ) leases
          )
        );

        toh.meta.sops.secrets.${caSecret} = {
          key = "openssl-ca-public";
          public = true;
        };
        toh.meta.sops.secrets.${publicSecret}.public = true;
        toh.meta.sops.secrets.${privateSecret}.mode = "0400";

        toh.meta.cryl.machine = [
          {
            lease = {
              generations = [
                {
                  generator = "tls-leaf";
                  arguments = {
                    common_name = "${config.toh.meta.machine.name}-lease";
                    organization = "ToH";
                    sans = [ config.toh.meta.network.ip ];
                    config = "lease-etcd-cert-config";
                    request_config = "lease-etcd-cert-request-config";
                    private = privateSecret;
                    request = "lease-etcd-cert-request";
                    ca_private = "cluster/openssl-ca-private";
                    ca_public = "cluster/openssl-ca-public";
                    serial = "cluster/openssl-ca-serial";
                    public = publicSecret;
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
