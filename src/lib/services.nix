{
  toh.lib.services = rec {
    proxyProtocols = [
      "tcp"
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
    ];

    sslTermination = [
      "terminate"
      "re-encrypt"
      "passthrough"
    ];
  };
}
