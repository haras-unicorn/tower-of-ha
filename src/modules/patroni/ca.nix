{
  toh.lib.nixosModules.services-patroni-ca =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.patroni;

      certs = tohLib.patroni.certs.root;

      ca = "${certs}/${tohLib.patroni.certs.ca}";

      proxyAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.postgresql.endpoint;
    in
    {
      options.toh.services = {
        patroni = {
          installCa = lib.mkEnableOption "patroni CA installation";
          generateCa = lib.mkEnableOption "patroni CA generation";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.installCa {
          toh.services.patroni.generateCa = true;

          sops.secrets."patroni-ca-public" = {
            path = ca;
            owner = config.services.patroni.user;
            group = config.services.patroni.group;
            mode = "0644";
          };
        })
        (lib.mkIf cfg.generateCa {
          toh.cryl.machine = [
            {
              patroni-ca = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/patroni-ca-public";
                      to = "patroni-ca-public";
                    };
                  }
                ];
              };
            }
          ];

          toh.cryl.cluster = lib.mkBefore [
            {
              patroni-ca = {
                generations = [
                  {
                    generator = "tls-root";
                    arguments = {
                      common_name = proxyAttrs.host;
                      organization = "ToH";
                      config = "patroni-ca-config";
                      private = "patroni-ca-private";
                      public = "patroni-ca-public";
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
