{ selfLib, lib, ... }:

{
  self.lib.url = {
    defaultPorts = {
      http = 80;
      https = 443;
      ssh = 22;
      dns = 53;
      smtp = 25;
      submission = 587;
      smtps = 465;
      imap = 143;
      imaps = 993;
      pop3 = 110;
      pop3s = 995;
      ldap = 389;
      ldaps = 636;
      postgresql = 5432;
      mysql = 3306;
      redis = 6379;
      rediss = 6380;
    };

    makePath =
      {
        basePath ? null,
        relativePath ? null,
      }:
      let
        unprefixedBasePath = lib.removeSuffix "/" (lib.removePrefix "/" basePath);
      in
      if relativePath != null then
        if lib.hasPrefix "/" relativePath then
          relativePath
        else if basePath != null then
          "/${unprefixedBasePath}/${relativePath}"
        else
          "/${relativePath}"
      else if basePath != null then
        "/${unprefixedBasePath}"
      else
        "";

    makeUrl =
      {
        protocol,
        domain ? null,
        user ? null,
        password ? null,
        host,
        port,
        path ? null,
        parameters ? null,
      }:
      "${protocol}://"
      + lib.optionalString (user != null) (
        lib.optionalString (domain != null) "${domain};"
        + user
        + lib.optionalString (password != null) ":${password}"
        + "@"
      )
      + host
      + lib.optionalString (
        !(selfLib.url.defaultPorts ? ${protocol}) || port != selfLib.url.defaultPorts.${protocol}
      ) ":${builtins.toString port}"
      + lib.optionalString (path != null && path != "") "/${lib.removePrefix "/" path}"
      + lib.optionalString (parameters != null && parameters != { }) (
        "?"
        + builtins.concatStringsSep "&" (
          lib.mapAttrsToList (name: value: "${name}=${builtins.toString value}") parameters
        )
      );
  };

  self.unitTests.url =
    let
      makePath = selfLib.url.makePath;
    in
    {
      test-make-path-empty = {
        expr = makePath { };
        expected = "";
      };

      test-make-path-base-only = {
        expr = makePath { basePath = "/api/"; };
        expected = "/api";
      };

      test-make-path-relative-only = {
        expr = makePath { relativePath = "health"; };
        expected = "/health";
      };

      test-make-path-base-and-relative = {
        expr = makePath {
          basePath = "/api";
          relativePath = "health";
        };
        expected = "/api/health";
      };

      test-make-path-absolute-relative-wins = {
        expr = makePath {
          basePath = "/api";
          relativePath = "/health";
        };
        expected = "/health";
      };

      test-make-url-default-port = {
        expr = selfLib.url.makeUrl {
          protocol = "https";
          host = "example.com";
          port = 443;
          path = "/api/health";
          parameters = {
            verbose = 1;
          };
        };
        expected = "https://example.com/api/health?verbose=1";
      };

      test-make-url-credentials-and-port = {
        expr = selfLib.url.makeUrl {
          protocol = "postgresql";
          user = "app";
          password = "secret";
          host = "db";
          port = 6432;
          path = "app";
        };
        expected = "postgresql://app:secret@db:6432/app";
      };
    };
}
