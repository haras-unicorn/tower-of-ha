{ self, ... }:

{
  flake.nixosModules.services-cockroachdb-builtin-backup =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    {
      options.toh = {
        cockroachdb = {
          enableBuiltinBackup = lib.mkEnableOption "CockroachDB automatic backup";
        };
      };

      config = lib.mkIf (config.toh.cockroachdb.enable && config.toh.cockroachdb.enableBuiltinBackup) {
        services.cockroachdb.init.sql.files = [ config.sops.secrets."cockroach-backup-init".path ];

        sops.secrets."cockroach-backup-init" = {
          owner = config.services.cockroachdb.user;
          group = config.services.cockroachdb.group;
          mode = "0400";
        };

        toh.cryl.host.cockroachdb-builtin-backup = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-backup-pass";
                to = "cockroach-backup-pass";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cloudflare-r2-cockroachdb-endpoint";
                to = "cloudflare-r2-cockroachdb-endpoint";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cloudflare-r2-cockroachdb-access-key-id";
                to = "cloudflare-r2-cockroachdb-access-key-id";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cloudflare-r2-cockroachdb-secret-access-key";
                to = "cloudflare-r2-cockroachdb-secret-access-key";
              };
            }
          ];
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "cockroach-backup-init";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    COCKROACH_BACKUP_PASS = "cockroach-backup-pass";

                    CLOUDFLARE_R2_COCKROACHDB_ENDPOINT = "cloudflare-r2-cockroachdb-endpoint";
                    CLOUDFLARE_R2_COCKROACHDB_ACCESS_KEY_ID = "cloudflare-r2-cockroachdb-access-key-id";
                    CLOUDFLARE_R2_COCKROACHDB_SECRET_ACCESS_KEY = "cloudflare-r2-cockroachdb-secret-access-key";
                  };
                };
                template =
                  let
                    backupConnectionStringTemplate =
                      "s3://cockroachdb/v1"
                      + "?AWS_REGION=auto"
                      + "&AWS_ENDPOINT={{CLOUDFLARE_R2_COCKROACHDB_ENDPOINT}}"
                      + "&AWS_ACCESS_KEY_ID={{CLOUDFLARE_R2_COCKROACHDB_ACCESS_KEY_ID}}"
                      + "&AWS_SECRET_ACCESS_KEY={{CLOUDFLARE_R2_COCKROACHDB_SECRET_ACCESS_KEY}}";
                  in
                  ''
                    create user if not exists backup password '{{COCKROACH_BACKUP_PASS}}';

                    grant system backup, externalioimplicitaccess to backup;

                    set role backup;

                    create schedule if not exists cluster_daily
                    for backup into '${backupConnectionStringTemplate}'
                    recurring '@daily' full backup always
                    with schedule options first_run = now;

                    reset role;
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

        toh.cryl.cluster.cockroachdb-builtin-backup = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/cockroach-backup-pass";
                to = "cockroach-backup-pass";
                allow_fail = true;
              };
            }
          ];
          generations = [
            {
              generator = "key";
              arguments = {
                name = "cockroach-backup-pass";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "cockroach-backup-pass";
                to = "${self.lib.cryl.directories.cluster}/cockroach-backup-pass";
              };
            }
          ];
        };
      };
    };
}
