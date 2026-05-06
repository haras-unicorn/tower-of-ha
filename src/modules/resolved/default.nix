# TODO: dnssec and dnsovertls

{
  toh.lib.nixosModules.services-resolved =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.resolved;
    in
    {
      options.toh.services = {
        resolved = {
          enable = lib.mkEnableOption "resolved";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.networkmanager.dns = "systemd-resolved";

        networking.nameservers = lib.mkBefore [
          # Cloudflare
          "1.1.1.1"
          "1.0.0.1"

          # Google
          "8.8.8.8"
          "8.8.4.4"
        ];

        services.resolved.enable = true;
        services.resolved.fallbackDns = [ ];
        services.resolved.dnssec = "false";
        services.resolved.dnsovertls = "false";
        services.resolved.llmnr = "false";
      };
    };
}
