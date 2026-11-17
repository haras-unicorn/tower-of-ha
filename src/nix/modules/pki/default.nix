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
          installCa = lib.mkEnableOption "ToH PKI SSL CA installation";
          generateCa = lib.mkEnableOption "ToH PKI SSL CA generation";
        };
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = [
            pkgs.openssl
          ];
        }
        (lib.mkIf cfg.installCa {
          toh.pki.generateCa = true;

          security.pki.certificatePaths = [ config.toh.meta.sops.secrets."openssl-ca-public".path ];
          security.pki.buildWithService = true;

          toh.meta.sops.secrets."openssl-ca-public" = {
            owner = "root";
            group = "root";
            mode = "0644";
          };
        })
        (lib.mkIf cfg.generateCa {
          toh.meta.cryl.machine = [
            {
              openssl = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/openssl-ca-public";
                      to = "openssl-ca-public";
                    };
                  }
                ];
              };
            }
          ];

          toh.meta.cryl.cluster = lib.mkBefore [
            {
              openssl = {
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
              };
            }
          ];
        })
      ];
    };
}
