{ lib, ... }:

{
  toh.lib.strings = {
    indentTail =
      indentation: string:
      builtins.concatStringsSep "\n" (
        lib.imap0 (index: line: if index == 0 || line == "" then line else "${indentation}${line}") (
          lib.splitString "\n" string
        )
      );
  };
}
