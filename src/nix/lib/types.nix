{ lib, ... }:

{
  toh.lib.types = {
    regexOrString = lib.types.str // {
      description =
        "Regex if wrapped with forward slashes"
        + " or a string if wrapped with single quotes"
        + " or not wrapped at all";
    };
  };
}
