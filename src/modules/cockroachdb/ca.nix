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
      certs = "/var/lib/cockroachdb/.certs";

      anyMachines = tohLib.anyServiceMachines "cockroachdb";
    in
    {
      sops.secrets."cockroach-ca-public" = lib.mkIf anyMachines {
        path = "${certs}/ca.crt";
        owner = config.services.cockroachdb.user;
        group = config.services.cockroachdb.group;
        mode = "0644";
      };

      toh.cryl.machine.cockroachdb-ca = lib.mkIf anyMachines {
        imports = [
          {
            importer = "copy";
            arguments = {
              from = "${tohLib.secrets.directories.cluster}/cockroach-ca-private";
              to = "cockroach-ca-private";
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${tohLib.secrets.directories.cluster}/cockroach-ca-public";
              to = "cockroach-ca-public";
            };
          }
        ];
      };

      toh.cryl.cluster.cockroachdb-ca = lib.mkIf anyMachines {
        imports = [
          {
            importer = "copy";
            arguments = {
              from = "${tohLib.secrets.directories.cluster}/cockroach-ca-private";
              to = "cockroach-ca-private";
              allow_fail = true;
            };
          }
          {
            importer = "copy";
            arguments = {
              from = "${tohLib.secrets.directories.cluster}/cockroach-ca-public";
              to = "cockroach-ca-public";
              allow_fail = true;
            };
          }
        ];
        generations = lib.mkBefore [
          {
            generator = "cockroach-ca";
            arguments = {
              private = "cockroach-ca-private";
              public = "cockroach-ca-public";
            };
          }
        ];
        exports = [
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-ca-private";
              to = "${tohLib.secrets.directories.cluster}/cockroach-ca-private";
            };
          }
          {
            exporter = "copy";
            arguments = {
              from = "cockroach-ca-public";
              to = "${tohLib.secrets.directories.cluster}/cockroach-ca-public";
            };
          }
        ];
      };
    };
}
