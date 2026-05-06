{
  toh.lib.nixosModules.services-cockroachdb-sql =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.services.cockroachdb;
    in
    {
      options.services.cockroachdb = {
        sql.port = lib.mkOption {
          type = lib.types.port;
          default = 26258;
          description = "SQL listening port";
        };

        sql.address = lib.mkOption {
          type = lib.types.str;
          default = "localhost";
          description = "SQL listening address";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.firewall.allowedTCPPorts = lib.optional cfg.openPorts cfg.sql.port;

        services.cockroachdb.extraArgs = [
          "--sql-addr"
          "${cfg.sql.address}:${builtins.toString cfg.sql.port}"
        ];
      };
    };
}
