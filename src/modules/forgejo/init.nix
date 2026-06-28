{
  toh.lib.nixosModules.services-forgejo-init =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      oidcConfg = config.toh.meta.oidc;
      oidcClient = config.toh.meta.oidc.clients.forgejo;

      forgejoCfg = config.services.forgejo;
      configFile = cfg.config.path;

      owner = "forgejo";
      group = "forgejo-config";

      dbInstance = config.toh.meta.database.instances.forgejo;

      runnerMachines = builtins.filter (
        machine: machine.config.toh.services.forgejo.runner.enable
      ) config.toh.meta.cluster.machinea;
    in
    {
      options.toh.services = {
        forgejo = {
          init = {
            enable = lib.mkEnableOption "Forgejo initialization" // {
              default = cfg.enable;
            };
          };
        };
      };

      config = lib.mkIf cfg.init.enable {
        toh.overlays = lib.mkMerge [
          (tohLib.cli.makeOverlays {
            name = "forgejo-auth";
            runtimeInputs = pkgs: [
              forgejoCfg.package
            ];
            textFile = ./auth.nu;
            textVariables = {
              TOH_FORGEJO_CONFIG = configFile;
              TOH_FORGEJO_OAUTH_BASE_URL = oidcConfg.baseUrl;
              TOH_FORGEJO_OAUTH_CLIENT_SECRET = oidcClient.clientSecret;
            };
          })
          (tohLib.cli.makeOverlays {
            name = "forgejo-actions";
            runtimeInputs = pkgs: [
              forgejoCfg.package
              pkgs.usql
            ];
            textFile = ./actions.nu;
            textVariables = {
              TOH_FORGEJO_CONFIG = configFile;
              TOH_FORGEJO_DB_INSTANCE = builtins.toJSON dbInstance;
              TOH_FORGEJO_RUNNERS = builtins.toJSON (
                builtins.map (machine: {
                  name = machine.name;
                  secret = config.toh.meta.sopse.secrets."forgejo-runner-machine-${machine.name}-secret".path;
                }) runnerMachines
              );
            };
          })
        ];

        systemd.services.forgejo-auth = {
          after = [ "forgejo.service" ];
          requires = [ "forgejo.service" ];
          path = [ pkgs.tohPackages.forgejo-auth ];
          script = "forgejo-auth";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = owner;
            Group = group;
            SupplementaryGroups = "forgejo-config";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
          };
        };

        systemd.services.forgejo-actions = {
          after = [ "forgejo.service" ];
          requires = [ "forgejo.service" ];
          path = [ pkgs.tohPackages.forgejo-actions ];
          script = "forgejo-actions";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = owner;
            Group = group;
            SupplementaryGroups = "forgejo-config";
            TimeoutStartSec = "infinity";
            Restart = "on-failure";
          };
        };
      };
    };
}
