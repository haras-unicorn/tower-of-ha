{
  toh.lib.services = {
    proxyProtocols = [
      "tcp"
      "http"
      "https"
    ];

    layer7Protocols = [
      "tcp"
      "http"
      "https"
      "postgresql"
      "mysql"
      "smb"
    ];

    sslTermination = [
      "terminate"
      "re-encrypt"
      "passthrough"
    ];
  };
}
