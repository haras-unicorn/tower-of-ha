{ self, ... }:

let
  userCertsPath = "~/.cockroach-certs";
  userEnvPath = "${userCertsPath}/user.env";
in
{
  overlayList = [
    {
      name = "cli-cockroachdb-user";
      value = self.lib.cli.makeOverlay {
        extraRuntimeInputs = pkgs: [
          pkgs.cockroachdb
          pkgs.vault
        ];
        extraText = ''
          $env.TOH_COCKROACHDB_USER_ENV_PATH = "${userEnvPath}"

          ${builtins.readFile ./user.nu}
        '';
      };
    }
  ];

  flake.nixosModules.services-cockroachdb-user =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.services.cockroachdb;

      user = config.toh.host.user;
      hostname = config.toh.host.name;

      clientCerts = builtins.replaceStrings [ "~" ] [ config.users.users.${user}.home ] userCertsPath;

      clientEnv = builtins.replaceStrings [ "~" ] [ config.users.users.${user}.home ] userEnvPath;

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
    in
    {
      sops.secrets."cockroach-${user}-ca-public" = {
        key = "cockroach-ca-public";
        path = "${clientCerts}/ca.crt";
        owner = user;
        group = user;
        mode = "0644";
      };
      sops.secrets."cockroach-${hostname}-${user}-public" = {
        path = "${clientCerts}/client.${user}.crt";
        owner = user;
        group = user;
        mode = "0644";
      };
      sops.secrets."cockroach-${hostname}-${user}-private" = {
        path = "${clientCerts}/client.${user}.key";
        owner = user;
        group = user;
        mode = "0400";
      };
      sops.secrets."cockroach-${user}-env" = {
        path = clientEnv;
        owner = user;
        group = user;
        mode = "0400";
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

      toh.cryl.host.cockroachdb-user = {
        generations = [
          {
            generator = "cockroach-client-cert";
            arguments = {
              ca_private = "cockroach-ca-private";
              ca_public = "cockroach-ca-public";
              private = "cockroach-${hostname}-${user}-private";
              public = "cockroach-${hostname}-${user}-public";
              user = user;
              renew = true;
            };
          }
          {
            generator = "mustache";
            arguments = {
              name = "cockroach-${user}-env";
              renew = true;
              listing = {
                type = "map";
                value = {
                  COCKROACH_USER_PASS = "cockroach-${user}-pass";
                };
              };
              template =
                let
                  url =
                    "postgresql://${user}:{{COCKROACH_USER_PASS}}@${cockroachHost}"
                    + "?sslmode=verify-full"
                    + "&sslrootcert=${clientCerts}/ca.crt"
                    + "&sslcert=${clientCerts}/client.${user}.crt"
                    + "&sslkey=${clientCerts}/client.${user}.key";
                in
                ''
                  export COCKROACH_URL="${url}"

                  export PGUSER="${user}"
                  export PGPASSWORD="{{COCKROACH_USER_PASS}}"
                  export PGHOST="${postgresHost}"
                  export PGSSLMODE="verify-full"
                  export PGSSLROOTCERT="${clientCerts}/ca.crt"
                  export PGSSLCERT="${clientCerts}/client.${user}.crt"
                  export PGSSLKEY="${clientCerts}/client.${user}.key"
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
      toh.cryl.cluster.cockroachdb-user = {
        imports = [
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-${user}-pass";
              to = "cockroach-${user}-pass";
              allow_fail = true;
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-${user}-private";
              to = "cockroach-${user}-private";
              allow_fail = true;
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${self.lib.cryl.directories.cluster}/cockroach-${user}-public";
              to = "cockroach-${user}-public";
              allow_fail = true;
            };
          }
        ];
        generations = [
          {
            generator = "key";
            arguments = {
              name = "cockroach-${user}-pass";
            };
          }
          {
            generator = "cockroach-client-cert";
            arguments = {
              ca_private = "cockroach-ca-private";
              ca_public = "cockroach-ca-public";
              private = "cockroach-${user}-private";
              public = "cockroach-${user}-public";
              user = user;
              renew = true;
            };
          }
        ];
        exports = [
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-${user}-pass";
              to = "${self.lib.cryl.directories.cluster}/cockroach-${user}-pass";
            };
          }
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-${user}-private";
              to = "${self.lib.cryl.directories.cluster}/cockroach-${user}-private";
            };
          }
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-${user}-public";
              to = "${self.lib.cryl.directories.cluster}/cockroach-${user}-public";
            };
          }
        ];
      };
    };
}
