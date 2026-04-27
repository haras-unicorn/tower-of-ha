{ self, ... }:

{
  flake.nixosModules.services-avahi-geoclue2 =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.avahi-geoclue2;
    in
    {
      options.toh = {
        avahi-geoclue2 = {
          enable = lib.mkEnableOption "Avahi and Geoclue2";
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
        # sops.secrets."geoclue-static-geolocation" = {
        #   path = "/etc/geolocation";
        #   owner = "geoclue";
        #   group = "geoclue";
        #   mode = "0440";
        # };

        toh.cryl.host.geoclue2-avahi = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/geoclue-static-geolocation";
                to = "geoclue-static-geolocation";
              };
            }
          ];
        };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks.test-services-avahi-geoclue2-disabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-avahi-geoclue2-disabled";
        toh.test.disabledService.enable = true;
        toh.test.disabledService.module =
          { lib, ... }:
          {
            imports = [
              self.nixosModules.services-avahi-geoclue2
            ];
          };
        toh.test.disabledService.name = "geoclue2";

      };

      checks.test-services-avahi-geoclue2-enabled = pkgs.tohPackages.testers.runToHTest {
        name = "services-avahi-geoclue2-enabled";

        toh.test.cryl.cluster.avahi-geoclue2 = {
          generations = [
            {
              generator = "text";
              arguments = {
                name = "geoclue-static-geolocation";
                text = "1";
              };
            }
          ];
          exports = [
            {
              exporter = "copy";
              arguments = {
                from = "geoclue-static-geolocation";
                to = "${self.lib.cryl.directories.cluster}/geoclue-static-geolocation";
              };
            }
          ];
        };

        nodes.machine = {
          imports = [
            self.nixosModules.services-avahi-geoclue2
          ];

          toh.avahi-geoclue2.enable = true;
        };

        toh.test.commands.suffix = ''
          machine.wait_for_unit("avahi-daemon.service")
          machine.wait_for_unit("geoclue.service")
        '';
      };
    };
}
