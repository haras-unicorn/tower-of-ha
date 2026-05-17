{ lib, ... }:

{
  toh.lib.url = {
    makePath =
      {
        basePath ? null,
        relativePath ? null,
      }:
      if relativePath != null then
        if lib.hasPrefix "/" relativePath then
          relativePath
        else if basePath != null then
          "/${basePath}/${relativePath}"
        else
          "/${relativePath}"
      else if basePath != null then
        "/${basePath}"
      else
        "";

    makeUrl =
      {
        protocol,
        user ? null,
        password ? null,
        host,
        port,
        path ? null,
        parameters ? { },
      }:
      "${protocol}://"
      + lib.optionalString (user != null) (
        user + lib.optionalString (password != null) ":${password}" + "@"
      )
      + "${host}:${builtins.toString port}"
      + lib.optionalString (path != null) path
      + lib.optionalString (parameters != { }) (
        "?"
        + builtins.concatStringsSep "&" (
          builtins.map ({ name, value }: "${name}=${builtins.toString value}") (lib.attrsToList parameters)
        )
      );

  };
}
