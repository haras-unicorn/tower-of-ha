{
  toh.lib.nixosModules.ssl =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.ssl;
    in
    {
      options.toh = {
        ssl = {
          installCa = lib.mkEnableOption "ToH SSL CA installation" // {
            default = true;
          };

          generateCa = lib.mkEnableOption "ToH SSL CA generation";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.installCa {
          toh.ssl.generateCa = true;

          security.pki.certificatePaths = [ config.sops.secrets."openssl-ca-public".path ];
          security.pki.buildOnActivation = true;

          sops.secrets."openssl-ca-public" = {
            owner = "root";
            group = "root";
            mode = "0644";
          };
        })
        (lib.mkIf cfg.generateCa {
          toh.cryl.machine.openssl-ca = {
            generations = [
              {
                generator = "copy";
                arguments = {
                  from = "cluster/openssl-ca-public";
                  to = "openssl-ca-public";
                };
              }
              {
                generator = "copy";
                arguments = {
                  from = "cluster/openssl-ca-private";
                  to = "openssl-ca-private";
                };
              }
              {
                generator = "copy";
                arguments = {
                  from = "cluster/openssl-ca-serial";
                  to = "openssl-ca-serial";
                };
              }
            ];
          };

          toh.cryl.cluster.openssl = {
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
          };
        })
      ];
    };
}
