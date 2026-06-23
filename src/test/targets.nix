{
  toh.lib.test.nixosModules.targets = {
    systemd.targets.toh-secrets-initialized = {
      requires = [ "local-fs.target" ];
      after = [ "local-fs.target" ];
    };

    systemd.targets.toh-network-online = {
      requires = [
        "network-online.target"
      ];
      after = [
        "network-online.target"
      ];
    };

    systemd.targets.toh-name-service-online = {
      requires = [
        "toh-network-online.target"
        "nss-lookup.target"
      ];
      after = [
        "toh-network-online.target"
        "nss-lookup.target"
      ];
    };

    systemd.targets.toh-time-synchronized = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "time-sync.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "time-sync.target"
      ];
    };

    systemd.targets.toh-config-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-database-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-filesystem-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-ldap-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-kv-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-oidc-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-s3-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };

    systemd.targets.toh-email-online = {
      requires = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
      after = [
        "toh-network-online.target"
        "toh-name-service-online.target"
        "toh-time-synchronized.target"
      ];
    };
  };

  toh.lib.test.nixosModules.target-dependants = {
    systemd.targets.toh-secrets-initialized = {
      description = "ToH secrets initialized";
      wantedBy = [ "sysinit.target" ];
      before = [ "sysinit.target" ];
    };

    systemd.targets.toh-network-online = {
      description = "ToH network online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-name-service-online = {
      description = "ToH name service online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-time-synchronized = {
      description = "ToH time synchronized";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-config-online = {
      description = "ToH configuration store online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-database-online = {
      description = "ToH database online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-filesystem-online = {
      description = "ToH filesystem online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-ldap-online = {
      description = "ToH LDAP online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-kv-online = {
      description = "ToH KV store online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-oidc-online = {
      description = "ToH OIDC online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-s3-online = {
      description = "ToH S3 online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };

    systemd.targets.toh-email-online = {
      description = "ToH email online";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
    };
  };
}
