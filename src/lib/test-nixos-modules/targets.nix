{
  libAttrs.test.nixosModules.targets =
    { lib, ... }:
    {
      systemd.targets.toh-network-online = {
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
      systemd.targets.toh-time-synchronized = {
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
      systemd.targets.toh-database-initialized = {
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
      systemd.targets.toh-filesystem-initialized = {
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
    };
}
