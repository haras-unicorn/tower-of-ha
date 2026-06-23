{
  toh.lib.nixosModules.services-geoclue =
    {
      config,
      lib,
      tohLib,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.geoclue;

      locality = config.toh.meta.locality;
    in
    {
      options.toh.services = {
        geoclue = {
          enable = lib.mkEnableOption "Geoclue";

          staticGeolocationSecret = lib.mkOption {
            type = lib.types.str;
            default = "${locality.region}-${locality.dataCenter}-geoclue-static-geolocation";
            description = "Static geoclue geolocation configuration file";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # NOTE: https://github.com/NixOS/nixpkgs/issues/329522
        services.avahi.enable = true;
        services.geoclue2.enable = true;
        services.geoclue2.enableStatic = true;
        # NOTE: disable the generated one from nixpkgs
        environment.etc.geolocation.enable = lib.mkForce false;

        location.provider = "geoclue2";
        i18n.defaultLocale = "en_US.UTF-8";
        services.automatic-timezoned.enable = true;

        # NOTE: https://github.com/NixOS/nixpkgs/issues/293212#issuecomment-2319051915
        # toh.meta.sops.secrets."geoclue-static-geolocation" = {
        #   path = "/etc/geolocation";
        #   owner = "geoclue";
        #   group = "geoclue";
        #   mode = "0440";
        # };

        toh.meta.cryl.machine = [
          {
            geoclue = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "external/${cfg.staticGeolocationSecret}";
                    to = "geoclue-static-geolocation";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
