{ selfLib, lib, ... }:

{
  self.lib.strings = {
    indentTail =
      indentation: string:
      builtins.concatStringsSep "\n" (
        lib.imap0 (index: line: if index == 0 || line == "" then line else "${indentation}${line}") (
          lib.splitString "\n" string
        )
      );

    # NOTE: only for ASCII text, because nix has no way to get at the bytes
    # of other characters
    toHex =
      string:
      lib.concatMapStrings (
        character:
        lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString (lib.strings.charToInt character)))
      ) (lib.stringToCharacters string);
  };

  self.unitTests.strings = {
    test-to-hex-text = {
      expr = selfLib.strings.toHex "+OK";
      expected = "2b4f4b";
    };

    test-to-hex-control-characters = {
      expr = selfLib.strings.toHex "\r\n";
      expected = "0d0a";
    };

    test-to-hex-empty = {
      expr = selfLib.strings.toHex "";
      expected = "";
    };
  };
}
