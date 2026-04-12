{
  flake.nixosModules.capabilities-targets = {
    systemd.targets.toh-network-online = {
      description = "ToH network online";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.targets.toh-time-synchronized = {
      description = "ToH time synchronized";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.targets.toh-database-initialized = {
      description = "ToH database initialized";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.targets.toh-filesystem-initialized = {
      description = "ToH filesystem initialized";
      wantedBy = [ "multi-user.target" ];
    };
  };
}
