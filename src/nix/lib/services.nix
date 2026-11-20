{ selfLib, lib, ... }:

let
  proxyProtocols = [
    "tcp"
    "submit"
    "http"
    "https"
  ];

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
  ++ selfLib.database.protocols;
in
{
  self.lib.services = {
    inherit proxyProtocols extraLayer7Protocols;

    layer7Protocols = proxyProtocols ++ extraLayer7Protocols;

    sslTermination = [
      "terminate"
      "re-encrypt"
      "passthrough"
    ];

    # NOTE: only HTTP and HTTPS endpoints can have a route, the endpoints of
    # every other protocol have no such attribute
    routeOf = service: (selfLib.services.endpoint.toAttrs service.endpoint).route or null;

    # NOTE: the order a proxy has to try the routes in, so that every proxy
    # implementation sorts the same way; priority comes first and the name
    # only breaks a tie, so the result does not depend on the machines
    routes =
      serviceNamesToMachineServices:
      lib.sort (a: b: a.priority < b.priority || (a.priority == b.priority && a.name < b.name)) (
        lib.concatLists (
          lib.mapAttrsToList (
            name: services:
            let
              route = selfLib.services.routeOf (builtins.head services);
            in
            lib.optional (route != null) {
              inherit name;
              inherit (route) service priority paths;
            }
          ) serviceNamesToMachineServices
        )
      );

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
          attrs = selfLib.services.endpoint.toAttrs endpoint;

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
            selfLib.url.makeUrl {
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
            path = selfLib.url.makePath {
              basePath = attrs.path or null;
              relativePath = path;
            };
            parameters = query;
          }
        else if builtins.elem attrs.protocol selfLib.database.protocols then
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

  self.unitTests.services =
    let
      route = priority: {
        endpoint.https.route = {
          service = "web";
          inherit priority;
          paths = [ { prefix = "/"; } ];
        };
      };

      names = services: builtins.map (route: route.name) (selfLib.services.routes services);
    in
    {
      test-routes-skip-services-without-a-route = {
        expr = names {
          web = [ { endpoint.https.route = null; } ];
          database = [ { endpoint.tcp = { }; } ];
          worker = [ (route 0) ];
        };
        expected = [ "worker" ];
      };

      test-routes-lower-priority-first = {
        expr = names {
          a = [ (route 0) ];
          b = [ (route (-1)) ];
          c = [ (route 1) ];
        };
        expected = [
          "b"
          "a"
          "c"
        ];
      };

      test-routes-name-breaks-a-tie = {
        expr = names {
          b = [ (route 0) ];
          a = [ (route 0) ];
        };
        expected = [
          "a"
          "b"
        ];
      };
    };
}
