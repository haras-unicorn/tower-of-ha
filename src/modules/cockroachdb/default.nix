{
  toh.lib.nixosModules.services-cockroachdb =
    {
      lib,
      tohLib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;

      machines = tohLib.serviceMachines "cockroachdb";

      serviceCfg = config.services.cockroachdb;

      # NOTE: https://www.cockroachlabs.com/docs/stable/cockroach-start
      joinMachines = builtins.tail (lib.lists.sublist 0 5 machines);

      join = builtins.concatStringsSep "," (
        builtins.map (
          machine:
          machine.services.cockroachdb.listen.address
          + ":"
          + builtins.toString machine.services.cockroachdb.listen.port
        ) joinMachines
      );
    in
    {
      options.toh.services = {
        cockroachdb = {
          enable = lib.mkEnableOption "CockroachDB";
        };
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = (builtins.length machines) == 0 || (builtins.length machines) > 1;
              message = ''
                CockroachDB requires at least two machines to form a cluster.
              '';
            }
          ];
        }
        (lib.mkIf cfg.enable {
          services.cockroachdb.enable = true;
          services.cockroachdb.join = join;
          services.cockroachdb.openPorts = true;
          services.cockroachdb.certsDir = tohLib.cockroachdb.certs.root;
          services.cockroachdb.http.address = config.toh.meta.network.ip;
          services.cockroachdb.listen.address = config.toh.meta.network.ip;
          services.cockroachdb.listen.port = 26258;
          services.cockroachdb.sql.address = config.toh.meta.network.ip;
          services.cockroachdb.sql.port = 26257;
          services.cockroachdb.locality =
            "region=${config.toh.locality.region}" + ",datacenter=${config.toh.locality.dataCenter}";
          services.cockroachdb.extraArgs = [
            "--background"
            "--logtostderr=WARNING"
            "--max-offset=5s"
          ];

          services.cockroachdb.init.enable = true;
          services.cockroachdb.init.hash = config.toh.meta.source.hash;
          systemd.targets.toh-database-initialized = {
            wantedBy = [ "cockroachdb.service" ];
            bindsTo = [
              "cockroachdb-initialization.service"
              "cockroachdb.service"
            ];
            after = [
              "cockroachdb-initialization.service"
              "cockroachdb.service"
            ];
          };

          systemd.services.cockroachdb.serviceConfig = {
            Type = lib.mkForce "forking";
            Restart = lib.mkForce "always";
          };
          systemd.services.cockroachdb.wantedBy = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.cockroachdb.after = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.cockroachdb.requires = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];

          environment.systemPackages = [
            pkgs.cockroachdb
            pkgs.postgresql
          ];

          programs.rust-motd.settings = {
            service_status = {
              CockroachDB = "cockroachdb";
            };
          };

          sops.secrets."cockroach-public" = {
            path = "${tohLib.cockroachdb.certs.root}/node.crt";
            owner = config.services.cockroachdb.user;
            group = config.services.cockroachdb.group;
            mode = "0644";
          };

          sops.secrets."cockroach-private" = {
            path = "${tohLib.cockroachdb.certs.root}/node.key";
            owner = config.services.cockroachdb.user;
            group = config.services.cockroachdb.group;
            mode = "0400";
          };

          toh.meta.services = [
            {
              name = "cockroachdb";
              port = serviceCfg.http.port;
              tls = true;
              health = "https:///health";
            }
          ];

          toh.cryl.machine.cockroachdb = {
            generations = [
              {
                generator = "cockroach-node-cert";
                arguments = {
                  ca_private = "cockroach-ca-private";
                  ca_public = "cockroach-ca-public";
                  hosts = [
                    "localhost"
                    "127.0.0.1"
                    config.toh.meta.network.ip
                    "cockroachdb.${config.toh.meta.domains.service}"
                  ];
                  private = "cockroach-private";
                  public = "cockroach-public";
                  renew = true;
                };
              }
            ];
          };

          toh.services.cockroachdb.installCa = true;
        })
      ];
    };
}
