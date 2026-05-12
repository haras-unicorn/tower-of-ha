{
  toh.lib.test.nixosModules.targets = {
    systemd.targets.toh-network-online = {
      requires = [
        "network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };
    systemd.targets.toh-time-synchronized = {
      requires = [
        "network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };
    systemd.targets.toh-config-initialized = {
      requires = [
        "network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };
    systemd.targets.toh-database-initialized = {
      requires = [
        "network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };
    systemd.targets.toh-filesystem-initialized = {
      requires = [
        "network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
    };
  };
}
