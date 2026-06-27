{ lib, tohLib, ... }:

{
  toh.lib.url = {
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
    };

    makePath =
      {
        basePath ? null,
        relativePath ? null,
      }:
      let
        unprefixedBasePath = lib.removePrefix basePath;
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
        port != (builtins.getAttr protocol tohLib.url.defaultPorts)
      ) ":${builtins.toString port}"
      + lib.optionalString (path != null && path != "") "/${lib.removePrefix "/" path}"
      + lib.optionalString (parameters != null && parameters != { }) (
        "?"
        + builtins.concatStringsSep "&" (
          lib.mapAttrsToList (name: value: "${name}=${builtins.toString value}") parameters
        )
      );
  };
}
