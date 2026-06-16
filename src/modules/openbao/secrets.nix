{
  toh.lib.nixosModules.services-openbao-secrets =
    {
      config,
      lib,
      pkgs,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.openbao;
    in
    {
      options.toh.services = {
        openbao = {
          secrets = {
            enable = lib.mkEnableOption "OpenBao secret management" // {
              default = cfg.enable;
            };
          };
        };
      };

      config = lib.mkIf cfg.secrets.enable {
        toh.overlays = tohLib.cli.makeOverlays {
          name = "openbao-secrets";
          runtimeInputs = pkgs: [
            pkgs.openbao
            pkgs.ipcalc
            pkgs.rustscan
            pkgs.curl
          ];
          textFile = ./secrets.nu;
          textVariables = {
            TOH_OPENBAO_KEYS_MOUNT = config.toh.meta.secrets.keys.mount;
            TOH_OPENBAO_AGE_PATH = config.toh.meta.secrets.files.age;
            TOH_OPENBAO_RESPONSE_PATH = config.toh.meta.secrets.files.response;
            TOH_OPENBAO_METADATA_PATH = config.toh.meta.secrets.files.metadata;
            TOH_OPENBAO_TOKEN_PATH = config.toh.meta.secrets.files.token;
            TOH_OPENBAO_MACHINE_NAME = config.toh.meta.machine.name;
            TOH_OPENBAO_MACHINES_KEY = config.toh.meta.secrets.keys.machines;
            TOH_OPENBAO_AGE_KEY = config.toh.meta.secrets.keys.age;
          };
        };

        systemd.services.openbao-age-key-fetch = {
          description = "OpenBao age key fetch";
          path = [ pkgs.tohPackages.openbao-secrets ];
          script = "openbao-secrets fetch-age-key";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          unitConfig = {
            DefaultDependencies = "no";
            RequiresMountsFor = [
              config.toh.meta.secrets.files.age
              config.toh.meta.secrets.files.response
              config.toh.meta.secrets.files.metadata
              config.toh.meta.secrets.files.token
            ];
          };
        };

        systemd.services.openbao-age-key-shred = {
          description = "OpenBao age key shred";
          path = [ pkgs.tohPackages.openbao-secrets ];
          script = "openbao-secrets shred-age-key";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          unitConfig = {
            DefaultDependencies = "no";
            RequiresMountsFor = [
              config.toh.meta.secrets.files.age
              config.toh.meta.secrets.files.response
              config.toh.meta.secrets.files.metadata
              config.toh.meta.secrets.files.token
            ];
          };
        };

        toh.services.openbao.token.enable = true;
      };
    };
}
