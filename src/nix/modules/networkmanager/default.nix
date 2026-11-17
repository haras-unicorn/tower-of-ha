{
  toh.lib.nixosModules.services-networkmanager =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.networkmanager;
    in
    {
      options.toh.services = {
        networkmanager = {
          enable = lib.mkEnableOption "NetworkManager";
        };
      };

      config = lib.mkIf cfg.enable {
        networking.nftables.enable = true;
        networking.firewall.enable = true;

        networking.networkmanager.enable = true;
        systemd.network.wait-online.enable = false;

        programs.rust-motd.settings = {
          service_status = {
            Network = "systemd-networkd";
          };
        };
      };
    };
}
