{ selfLib, ... }:

{
  self.nixosModules.services-openbao-token.flake = true;
  self.nixosModules.services-openbao-token.value =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.openbao;

      user = selfLib.openbao.user;
      group = selfLib.openbao.group;

      anyMachines = selfLib.cluster.anyServiceMachines config "openbao";

      hours = 2;
      refreshHours = hours / 2;
    in
    {
      options.toh.services = {
        openbao = {
          token = {
            enable = lib.mkEnableOption "OpenBao token management" // {
              # NOTE: the init makes a user for every machine of the cluster,
              # so every machine has the password to get a token with
              default = anyMachines;
              defaultText = lib.literalExpression "true when a machine of the cluster runs OpenBao";
            };
          };
        };
      };

      config = lib.mkIf cfg.token.enable {
        toh.overlays = selfLib.cli.makeOverlays {
          name = "openbao-token";
          runtimeInputs = pkgs: [ pkgs.openbao ];
          textFile = ./token.nu;
          textVariables = {
            TOH_OPENBAO_TOKEN_PATH = config.toh.meta.secrets.files.token;
            TOH_OPENBAO_RESPONSE_PATH = config.toh.meta.secrets.files.response;
            TOH_OPENBAO_MACHINE_USERNAME = config.toh.meta.machine.name;
            TOH_OPENBAO_MACHINE_PASSWORD_PATH =
              config.toh.meta.sops.secrets."openbao-machine-${config.toh.meta.machine.name}-pass".path;
            TOH_OPENBAO_ADDRESS = selfLib.services.endpoint.toUrl config.toh.meta.proxies.secrets.endpoint { };
          };
        };

        systemd.services.openbao-fetch-token = {
          description = "Fetch a two hour token from OpenBao";
          wantedBy = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
            "toh-name-service-online.target"
          ];
          after = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
            "toh-name-service-online.target"
          ];
          path = [ pkgs.tohPackages.openbao-token ];
          script = "openbao-token ${builtins.toString hours}";
          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = "10s";
          };
        };

        systemd.timers.openbao-fetch-token = {
          description = "OpenBao token fetch timer for every hour";
          wantedBy = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
            "toh-name-service-online.target"
          ];
          after = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
            "toh-name-service-online.target"
          ];
          timerConfig = {
            Unit = "openbao-fetch-two-hour-token.service";
            OnUnitActiveSec = "${builtins.toString refreshHours}h";
            Persistent = true;
          };
        };

        toh.meta.sops.secrets."openbao-machine-${config.toh.meta.machine.name}-pass" = {
          owner = user;
          group = group;
          mode = "0400";
        };

        toh.meta.cryl.machine = [
          {
            "openbao-${config.toh.meta.machine.name}-password" = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/openbao-machine-${config.toh.meta.machine.name}-pass";
                    to = "openbao-machine-${config.toh.meta.machine.name}-pass";
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            "openbao-${config.toh.meta.machine.name}-password" = {
              generations = [
                {
                  generator = "key";
                  arguments = {
                    name = "openbao-machine-${config.toh.meta.machine.name}-pass";
                  };
                }
              ];
            };
          }
        ];

        toh.services.openbao.createUserGroup = true;
      };
    };
}
