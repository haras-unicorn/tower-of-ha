{ tohLib, lib, ... }:

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
      "smb"
      "ldap"
      "ldaps"
      "redis"
      "rediss"
      "s3"
      "smtp"
      "imap"
    ]
    ++ tohLib.database.protocols;

    sslTermination = [
      "terminate"
      "re-encrypt"
      "passthrough"
    ];

    endpoint = {
      toAttrs =
        endpoint:
        let
          protocol = builtins.head (builtins.attrNames endpoint);
        in
        endpoint.${protocol} // { inherit protocol; };

      toUrl =
        endpoint:
        let
          attrs = tohLib.services.endpoint.toAttrs endpoint;

          host = attrs.host;
          port = attrs.port;
          protocol = if attrs ? layer7Protocol then attrs.layer7Protocol else attrs.protocol;
          base =
            {
              domain ? null,
              user ? null,
              password ? null,
              path ? null,
              parameters ? null,
            }:
            tohLib.url.makeUrl {
              inherit
                protocol
                domain
                user
                password
                host
                port
                path
                parameters
                ;
            };
        in
        if
          builtins.elem attrs.protocol [
            "http"
            "https"
          ]
        then
          {
            path ? null,
            query ? { },
          }:
          base {
            path = tohLib.url.makePath {
              basePath = attrs.path or null;
              relativePath = path;
            };
            parameters = query;
          }
        else if builtins.elem attrs.protocol tohLib.database.protocols then
          {
            user,
            password,
            database,
            parameters ? { },
          }:
          base {
            inherit user password parameters;
            path = database;
          }
        else if attrs.protocol == "smb" then
          {
            domain ? null,
            user ? null,
            password ? null,
            share,
            path ? null,
          }:
          base {
            inherit domain user password;
            path = share + lib.optionalString (path != null) ("/" + lib.removePrefix "/" path);
          }
        else if
          builtins.elem attrs.protocol [
            "ldap"
            "ldaps"
          ]
        then
          {
            path ? null,
          }:
          base {
            inherit path;
          }
        else
          base { };
    };
  };
}
