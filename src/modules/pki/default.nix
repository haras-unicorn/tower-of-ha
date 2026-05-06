{
  toh.lib.nixosModules.pki =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.pki;
    in
    {
      options.toh = {
        pki = {
          enable = lib.mkEnableOption "OpenSSL";
        };
      };

      config = lib.mkIf cfg.enable {
        security.pki.certificatePaths = [ config.sops.secrets."openssl-ca-public".path ];
        security.pki.buildOnActivation = true;

        sops.secrets."openssl-ca-public" = {
          owner = "root";
          group = "root";
          mode = "0644";
        };

        toh.cryl.machine.openssl-ca = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-public";
                to = "openssl-ca-public";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-private";
                to = "openssl-ca-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-serial";
                to = "openssl-ca-serial";
              };
            }
          ];
        };

        toh.cryl.cluster.openssl = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-private";
                to = "openssl-ca-private";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-public";
                to = "openssl-ca-public";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.cluster}/openssl-ca-serial";
                to = "openssl-ca-serial";
                allow_fail = true;
              };
            }
          ];
          generations = [
            {
              generator = "tls-root";
              arguments = {
                common_name = "toh";
                organization = "ToH";
                config = "openssl-ca-config";
                private = "openssl-ca-private";
                public = "openssl-ca-public";
              };
            }
            # TODO: with hex once in cryl
            {
              generator = "pin";
              arguments = {
                name = "openssl-ca-serial-pin";
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "openssl-ca-serial";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    OPENSSL_CA_SERIAL_PIN = "openssl-ca-serial-pin";
                  };
                };
                template = "{{OPENSSL_CA_SERIAL_PIN}}\n";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "openssl-ca-private";
                to = "${tohLib.secrets.directories.cluster}/openssl-ca-private";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "openssl-ca-public";
                to = "${tohLib.secrets.directories.cluster}/openssl-ca-public";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "openssl-ca-serial";
                to = "${tohLib.secrets.directories.cluster}/openssl-ca-serial";
              };
            }
          ];
        };
      };
    };
}
