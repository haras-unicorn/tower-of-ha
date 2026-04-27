{ self, ... }:

{
  flake.nixosModules.services-cockroachdb =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.services.cockroachdb;

      certs = "/var/lib/cockroachdb/.certs";

      user = config.toh.host.user;

      hosts = builtins.map (x: x.ip) (
        builtins.filter (
          x:
          if lib.hasAttrByPath [ "system" "toh" "cockroachdb" "enable" ] x then
            x.system.toh.cockroachdb.enable
          else
            false
        ) config.toh.host.hosts
      );

      # NOTE: https://www.cockroachlabs.com/docs/stable/cockroach-start
      joinHosts = builtins.tail (lib.lists.sublist 0 5 hosts);

      initHost = builtins.head joinHosts;

      join = builtins.concatStringsSep "," (
        builtins.map (x: "${x}:${builtins.toString cfg.listen.port}") joinHosts
      );
    in
    {
      options.toh = {
        cockroachdb = {
          enable = lib.mkEnableOption "CockroachDB";
        };
      };

      config = lib.mkIf config.toh.cockroachdb.enable {
        services.cockroachdb.extraArgs = [
          "--background"
          "--logtostderr=WARNING"
          "--max-offset=5s"
        ];
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

        services.cockroachdb.enable = true;
        services.cockroachdb.join = join;
        services.cockroachdb.openPorts = true;
        services.cockroachdb.certsDir = certs;
        services.cockroachdb.http.address = config.toh.host.ip;
        services.cockroachdb.listen.address = config.toh.host.ip;
        services.cockroachdb.listen.port = 26258;
        services.cockroachdb.sql.address = config.toh.host.ip;
        services.cockroachdb.sql.port = 26257;
        services.cockroachdb.locality =
          "region=${config.toh.locality.region}" + ",datacenter=${config.toh.locality.dataCenter}";

        services.cockroachdb.init.enable = true;
        services.cockroachdb.init.runner = config.toh.host.ip == initHost;
        services.cockroachdb.init.hash = self.narHash;
        services.cockroachdb.init.sql.files = lib.mkBefore [ config.sops.secrets."cockroach-init".path ];
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

        toh.database = {
          host = cfg.sql.address;
          port = cfg.sql.port;
          protocol = "postgresql://";
        };

        toh.services = [
          {
            name = "cockroachdb";
            port = cfg.http.port;
            tls = true;
            health = "https:///health";
          }
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
          path = "${certs}/node.crt";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0644";
        };
        sops.secrets."cockroach-private" = {
          path = "${certs}/node.key";
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };
        sops.secrets."cockroach-init" = {
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };

        toh.cryl.host.cockroachdb = {
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-init";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_ROOT_PASS = "cockroach-root-pass";
                    COCKROACH_USER_PASS = "cockroach-${user}-pass";
                  };
                };
                template = ''
                  alter user root with password '{{COCKROACH_ROOT_PASS}}';


                  create user if not exists ${user} password '{{COCKROACH_USER_PASS}}';

                  create database if not exists ${user};

                  use ${user};

                  alter default privileges for all roles in schema public grant all on tables to ${user};
                  alter default privileges for all roles in schema public grant all on sequences to ${user};
                  alter default privileges for all roles in schema public grant all on functions to ${user};

                  grant all on all tables in schema public to ${user};
                  grant all on all sequences in schema public to ${user};
                  grant all on all functions in schema public to ${user};

                  reset database;
                '';
              };
            }
            {
              generator = "cockroach-node-cert";
              arguments = {
                ca_private = "cockroach-ca-private";
                ca_public = "cockroach-ca-public";
                hosts = [
                  "localhost"
                  "127.0.0.1"
                  config.toh.host.ip
                  "cockroachdb.${config.toh.domains.service}"
                ];
                private = "cockroach-private";
                public = "cockroach-public";
                renew = true;
              };
            }
          ];
        };

        toh.cryl.host.cockroachdb-user-pass = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-${user}-pass";
                to = "cockroach-${user}-pass";
              };
            }
          ];
        };

        toh.cryl.host.cockroachdb-root-pass = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-root-pass";
                to = "cockroach-root-pass";
              };
            }
          ];
        };

        toh.cryl.host.cockroachdb-ca = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-ca-private";
                to = "cockroach-ca-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-ca-public";
                to = "cockroach-ca-public";
              };
            }
          ];
        };
      };
    };
}
