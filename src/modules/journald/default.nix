{
  toh.lib.nixosModules.services-journald =
    { lib, config, ... }:
    let
      cfg = config.toh.services.journald;
    in
    {
      options.toh.services = {
        journald = {
          enable = lib.mkEnableOption "journald extra config";
        };
      };

      config = lib.mkIf cfg.enable {
        services.journald.extraConfig = ''
          SystemMaxUse=750M
          SystemMaxFileSize=100M
          MaxRetentionSec=1month
        '';
      };
    };
}
