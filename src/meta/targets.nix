{
  toh.lib.nixosModules.meta-targets = {
    systemd.targets.toh-time-synchronized = {
      description = "ToH time synchronized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-network-online = {
      description = "ToH network online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-config-initialized = {
      description = "ToH configuration store initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-database-initialized = {
      description = "ToH database initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-filesystem-initialized = {
      description = "ToH filesystem initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-auth-ldap-initialized = {
      description = "ToH LDAP initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-kv-initialized = {
      description = "ToH KV store initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-auth-oidc-initialized = {
      description = "ToH OIDC initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-s3-initialized = {
      description = "ToH S3 initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-email-initialized = {
      description = "ToH email initialized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };
  };
}
