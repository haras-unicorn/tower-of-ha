{ self, ... }:

let
  rootEnvPath = "/etc/cockroachdb/root.env";
in
{
  overlayList = [
    {
      name = "cli-cockroachdb-root";
      value = self.lib.cli.makeOverlay {
        extraRuntimeInputs = pkgs: [
          pkgs.cockroachdb
          pkgs.vault
        ];
        extraText = ''
          $env.TOH_COCKROACHDB_ROOT_ENV_PATH = "${rootEnvPath}"

          ${builtins.readFile ./root.nu}
        '';
      };
    }
  ];

  flake.nixosModules.services-cockroachdb-root =
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

      hosts = builtins.filter (
        host:
        if lib.hasAttrByPath [ "system" "toh" "cockroachdb" "enable" ] host then
          host.system.toh.cockroachdb.enable
        else
          false
      ) config.toh.host.hosts;

      cockroachHost =
        if config.toh.cockroachdb.enable then
          "${cfg.sql.address}:${builtins.toString cfg.sql.port}"
        else if hosts == [ ] then
          lib.warn "No hosts for cockroachdb detected" ""
        else
          let
            host = builtins.head hosts;
            cfg = host.system.services.cockroachdb;
          in
          "${cfg.sql.address}:${builtins.toString cfg.sql.port}";

      postgresHost =
        if config.toh.cockroachdb.enable then
          "${cfg.sql.address}:${builtins.toString cfg.sql.port}"
        else
          builtins.concatStringsSep "," (
            builtins.map (
              host:
              let
                cfg = host.system.services.cockroachdb;
              in
              "${cfg.sql.address}:${builtins.toString cfg.sql.port}"
            ) hosts
          );

      hostname = config.toh.host.name;
    in
    {
      sops.secrets."cockroach-root-ca-public" = {
        key = "cockroach-ca-public";
        path = "${certs}/ca.crt";
        owner = config.services.cockroachdb.user;
        group = config.services.cockroachdb.group;
        mode = "0644";
      };
      sops.secrets."cockroach-root-${hostname}-public" = {
        path = "${certs}/client.root.crt";
        owner = config.services.cockroachdb.user;
        group = config.services.cockroachdb.group;
        mode = "0644";
      };
      sops.secrets."cockroach-root-${hostname}-private" = {
        path = "${certs}/client.root.key";
        owner = config.services.cockroachdb.user;
        group = config.services.cockroachdb.group;
        mode = "0400";
      };
      sops.secrets."cockroach-root-env" = {
        path = rootEnvPath;
        owner = "root";
        group = "root";
        mode = "0400";
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

      toh.cryl.host.cockroachdb-root = {
        generations = [
          {
            generator = "cockroach-client-cert";
            arguments = {
              ca_private = "cockroach-ca-private";
              ca_public = "cockroach-ca-public";
              private = "cockroach-root-${hostname}-private";
              public = "cockroach-root-${hostname}-public";
              user = "root";
            };
          }
          {
            generator = "mustache";
            arguments = {
              name = "cockroach-root-env";
              renew = true;
              listing = {
                type = "map";
                value = {
                  COCKROACH_ROOT_PASS = "cockroach-root-pass";
                };
              };
              template =
                let
                  url =
                    "postgresql://root:{{COCKROACH_ROOT_PASS}}@${cockroachHost}"
                    + "?sslmode=verify-full"
                    + "&sslrootcert=${certs}/ca.crt"
                    + "&sslcert=${certs}/client.root.crt"
                    + "&sslkey=${certs}/client.root.key";
                in
                ''
                  COCKROACH_URL="${url}"

                  PGUSER="root"
                  PGPASSWORD="{{COCKROACH_ROOT_PASS}}"
                  PGHOST="${postgresHost}"
                  PGSSLMODE="verify-full"
                  PGSSLROOTCERT="${certs}/ca.crt"
                  PGSSLCERT="${certs}/client.root.crt"
                  PGSSLKEY="${certs}/client.root.key"
                '';
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

      # FIXME: this only runs after cockroachdb-ca because it is alphabetically ordered after it
      toh.cryl.cluster.cockroachdb-root = {
        imports = [
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-root-pass";
              to = "cockroach-root-pass";
              allow_fail = true;
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-root-private";
              to = "cockroach-root-private";
              allow_fail = true;
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-root-public";
              to = "cockroach-root-public";
              allow_fail = true;
            };
          }
        ];
        generations = [
          {
            generator = "key";
            arguments = {
              name = "cockroach-root-pass";
            };
          }
          {
            generator = "cockroach-client-cert";
            arguments = {
              ca_private = "cockroach-ca-private";
              ca_public = "cockroach-ca-public";
              private = "cockroach-root-private";
              public = "cockroach-root-public";
              user = "root";
            };
          }
        ];
        exports = [
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-root-pass";
              to = "${self.lib.cryl.directories.cluster}/cockroach-root-pass";
            };
          }
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-root-private";
              to = "${self.lib.cryl.directories.cluster}/cockroach-root-private";
            };
          }
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-root-public";
              to = "${self.lib.cryl.directories.cluster}/cockroach-root-public";
            };
          }
        ];
      };
    };
}
