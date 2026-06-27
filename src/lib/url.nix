{ lib, ... }:

{
  toh.lib.url = {
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
      + "${host}:${builtins.toString port}"
      + lib.optionalString (path != null) "/${lib.removePrefix "/" path}"
      + lib.optionalString (parameters != null && parameters != { }) (
        "?"
        + builtins.concatStringsSep "&" (
          lib.mapAttrsToList (name: value: "${name}=${builtins.toString value}") parameters
        )
      );
  };
}
