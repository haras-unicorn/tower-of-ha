{
  flake.nixosModules.services =
    { lib, config, ... }:
    {
      options.toh = {
        services = {
          enable = lib.mkEnableOption "Critical services";
        };
      };

      config = lib.mkIf config.toh.services.enable {
        toh.nebula.enableLighthouseAndRelay = true;
        toh.ddns-updater.enable = true;
        toh.consul.enable = true;
        toh.traefik.enable = true;
        toh.cockroachdb.enable = true;
        toh.cockroachdb.enableBuiltinBackup = true;
        toh.seaweedfs.enable = true;
        toh.vault.enable = true;
        toh.vaultwarden.enable = true;
        toh.miniflux.enable = true;
        toh.backup.enable = true;
      };
    };
}
