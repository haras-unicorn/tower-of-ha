{
  toh.lib.nixosModules.services-cockroachdb-ca =
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
    in
    {
      options.toh.services = {
        cockroachdb = {
          installCa = lib.mkEnableOption "CockroachDB CA installation" // {
            default = tohLib.anyServiceMachines "cockroachdb";
          };

          generateCa = lib.mkEnableOption "CockroachDB CA generation";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.installCa {
          toh.services.cockroachdb.generateCa = true;

          sops.secrets."cockroach-ca-public-root" = {
            key = "cockroach-ca-public";
            path = "${tohLib.cockroachdb.certs.root}/ca.crt";
            owner = config.services.cockroachdb.user;
            group = config.services.cockroachdb.group;
            mode = "0644";
          };

          sops.secrets."cockroach-ca-public-user" = {
            key = "cockroach-ca-public";
            path = "${tohLib.cockroachdb.certs.user}/ca.crt";
            owner = config.services.cockroachdb.user;
            group = config.services.cockroachdb.group;
            mode = "0644";
          };
        })
        (lib.mkIf cfg.generateCa {
          toh.cryl.machine.cockroachdb-ca = {
            generations = [
              {
                generator = "copy";
                arguments = {
                  from = "cluster/cockroach-ca-public";
                  to = "cockroach-ca-public";
                };
              }
            ];
          };

          toh.cryl.cluster.cockroachdb-ca = {
            generations = [
              {
                generator = "cockroach-ca";
                arguments = {
                  private = "cockroach-ca-private";
                  public = "cockroach-ca-public";
                };
              }
            ];
          };
        })
      ];
    };
}
