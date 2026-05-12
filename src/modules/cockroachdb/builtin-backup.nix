{
  toh.lib.nixosModules.services-cockroachdb-builtin-backup =
    {
      lib,
      config,
      pkgs,
      utils,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;
    in
    {
      options.toh.services = {
        cockroachdb = {
          builtinBackup = {
            enable = lib.mkEnableOption "CockroachDB automatic backup";

            s3EndpointSecret = lib.mkOption {
              type = lib.types.str;
              description = "S3 endpoint secret for CockroachDB builtin backup endpoint";
            };

            s3AccessKeyIdSecret = lib.mkOption {
              type = lib.types.str;
              description = "S3 access key id secret for CockroachDB builtin backup endpoint";
            };

            s3SecretAccessKeySecret = lib.mkOption {
              type = lib.types.str;
              description = "S3 secret access key secret for CockroachDB builtin backup endpoint";
            };
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (!cfg.enable && cfg.builtinBackup.enable) {
          warnings = [
            ''
              ToH CockroachDB builtin backup enabled but CockroachDB disabled.
              ToH CockroachDB builtin backup will be disabled
              unless you set "toh.cockroachdb.enable" to true.
            ''
          ];
        })
        (lib.mkIf (cfg.enable && cfg.builtinBackup.enable) {
          services.cockroachdb.init.sql.files = [ config.sops.secrets."cockroach-builtin-backup-init".path ];

          sops.secrets."cockroach-builtin-backup-init" = {
            owner = config.services.cockroachdb.user;
            group = config.services.cockroachdb.group;
            mode = "0400";
          };

          toh.cryl.machine.cockroachdb-builtin-backup = {
            generations = [
              {
                generator = "mustache";
                arguments = {
                  name = "cockroach-builtin-backup-init";
                  renew = true;
                  listing = {
                    type = "map";
                    value = {
                      S3_ENDPOINT = "external/${cfg.builtinBackup.s3EndpointSecret}";
                      S3_ACCESS_KEY_ID = "external/${cfg.builtinBackup.s3AccessKeyIdSecret}";
                      S3_SECRET_ACCESS_KEY = "external/${cfg.builtinBackup.s3SecretAccessKeySecret}";
                      COCKROACH_BACKUP_PASS = "cluster/cockroach-backup-pass";
                    };
                  };
                  template =
                    let
                      backupConnectionStringTemplate =
                        "s3://cockroachdb/v1"
                        + "?AWS_REGION=auto"
                        + "&AWS_ENDPOINT={{S3_ENDPOINT}}"
                        + "&AWS_ACCESS_KEY_ID={{S3_ACCESS_KEY_ID}}"
                        + "&AWS_SECRET_ACCESS_KEY={{S3_SECRET_ACCESS_KEY}}";
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

          toh.cryl.cluster.cockroachdb-builtin-backup = {
            generations = [
              {
                generator = "key";
                arguments = {
                  name = "cockroach-backup-pass";
                };
              }
            ];
          };
        })
      ];
    };
}
