{
  toh.lib.services = rec {
    proxyProtocols = [
      "tcp"
      "submit"
      "http"
      "https"
    ];

    layer7Protocols = proxyProtocols ++ extraLayer7Protocols;

    extraLayer7Protocols = [
      "postgresql"
      "mysql"
      "smb"
      "ldap"
      "ldaps"
      "redis"
      "rediss"
      "s3"
      "smtp"
      "imap"
    ];

    sslTermination = [
      "terminate"
      "re-encrypt"
      "passthrough"
    ];
  };
}
