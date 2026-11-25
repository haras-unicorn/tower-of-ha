{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-database =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.database;

      app = selfLib.test.contract.app;
      table = "contract";
      row = "works";
      # NOTE: not the C locale, which the server may use anyway
      locale = "C.UTF-8";

      clientMeta = machines.client.toh.meta;
      host = clientMeta.database.host;

      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "database";
        write = ''lambda value: f"""contract-database "insert into ${table} values ('{value}')" """'';
        holds = ''lambda value: f"""contract-database "select value from ${table}" | grep -x '{value}'"""'';
      };
    in
    {
      options.toh.test.contracts.database = selfLib.test.contract.options "database" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                database = config.toh.meta.database;
                instance = database.instances.${app};

                connection = lib.concatStringsSep " " (
                  lib.mapAttrsToList (key: value: "${key}=${value}") {
                    host = database.host;
                    port = builtins.toString database.port;
                    dbname = instance.dbName;
                    user = instance.dbUser;
                    sslmode = "verify-full";
                    sslrootcert = instance.ssl.ca;
                    sslcert = instance.ssl.crt;
                    sslkey = instance.ssl.key;
                  }
                );

                clients.postgresql = pkgs.writeShellApplication {
                  name = "contract-database";
                  runtimeInputs = [
                    pkgs.postgresql
                    pkgs.util-linux
                  ];
                  text = ''
                    PGPASSWORD="$(cat ${instance.password})" \
                      exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      psql "${connection}" --no-psqlrc --tuples-only --no-align \
                      --command "$1"
                  '';
                };
              in
              {
                toh.meta.database.apps.${app} = {
                  dbLocale = locale;
                  init.sql.script = ''
                    create table ${table} (value text);
                  '';
                };

                environment.systemPackages = [ clients.${database.protocol} ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-database 'select count(*) from ${table}'", timeout=300)
              client.succeed("contract-database \"insert into ${table} values ('${row}')\"")
              read = client.succeed("contract-database 'select value from ${table}'").strip()
              assert read == "${row}", f"read back {read!r} instead of '${row}'"
              locales = client.succeed("contract-database 'select datcollate, datctype from pg_database where datname = current_database()'").strip()
              assert locales == "${locale}|${locale}", f"the database has the locales {locales!r} instead of '${locale}'"


              ${failover}
            '';
          }
        ]
      );
    };
}
