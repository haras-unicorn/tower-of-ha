{ lib, tohLib, ... }:

{
  toh.lib.regex = {
    isRegex = regexOrString: lib.hasPrefix "/" regexOrString && lib.hasSuffix "/" regexOrString;

    unwrapRegex = regex: builtins.substring 1 (builtins.stringLength regex - 2) regex;

    unwrapString =
      string:
      if lib.hasPrefix "'" string && lib.hasSuffix "'" string then
        builtins.substring 1 (builtins.stringLength string - 2) string
      else
        string;

    match =
      regexOrString: string:
      if tohLib.regex.isRegex regexOrString then
        builtins.match (tohLib.regex.unwrapRegex regexOrString) string
      else if (tohLib.regex.unwrapString regexOrString) == string then
        [ ]
      else
        null;
  };

  flake.tests.regex = {
    test-is-regex-unwrapped = {
      expr = tohLib.regex.isRegex "not a regex";
      expected = false;
    };
    test-is-regex-wrapped = {
      expr = tohLib.regex.isRegex "/a regex/";
      expected = true;
    };
    test-is-regex-only-start = {
      expr = tohLib.regex.isRegex "/not a regex";
      expected = false;
    };
    test-is-regex-only-end = {
      expr = tohLib.regex.isRegex "not a regex/";
      expected = false;
    };
    test-unwrap-regex-wrapped = {
      expr = tohLib.regex.unwrapRegex "/a regex/";
      expected = "a regex";
    };
    test-unwrap-regex-wrapped-twice = {
      expr = tohLib.regex.unwrapRegex "//a regex//";
      expected = "/a regex/";
    };
    test-unwrap-regex-empty = {
      expr = tohLib.regex.unwrapRegex "//";
      expected = "";
    };
    test-unwrap-string-wrapped = {
      expr = tohLib.regex.unwrapString "'not a regex'";
      expected = "not a regex";
    };
    test-unwrap-string-wrapped-twice = {
      expr = tohLib.regex.unwrapString "''not a regex''";
      expected = "'not a regex'";
    };
    test-unwrap-string-empty = {
      expr = tohLib.regex.unwrapString "''";
      expected = "";
    };
    test-match-regex-matches = {
      expr = tohLib.regex.match "/a .*/" "a regex";
      expected = [ ];
    };
    test-match-regex-does-not-match = {
      expr = tohLib.regex.match "/a .*/" "regex";
      expected = null;
    };
    test-match-regex-empty = {
      expr = tohLib.regex.match "//" "";
      expected = [ ];
    };
    test-match-regex-groups = {
      expr = tohLib.regex.match "/(a)(b)c/" "abc";
      expected = [
        "a"
        "b"
      ];
    };
    test-match-string-matches-unwrapped = {
      expr = tohLib.regex.match "not a regex" "not a regex";
      expected = [ ];
    };
    test-match-string-does-not-match-unwrapped = {
      expr = tohLib.regex.match "not a regex" "a regex";
      expected = null;
    };
    test-match-string-matches-wrapped = {
      expr = tohLib.regex.match "'not a regex'" "not a regex";
      expected = [ ];
    };
    test-match-string-does-not-match-wrapped = {
      expr = tohLib.regex.match "'not a regex'" "a regex";
      expected = null;
    };
    test-match-string-matches-wrapped-slashes = {
      expr = tohLib.regex.match "'/not a regex/'" "/not a regex/";
      expected = [ ];
    };
    test-match-string-matches-unwrapped-empty = {
      expr = tohLib.regex.match "" "";
      expected = [ ];
    };
    test-match-string-matches-wrapped-empty = {
      expr = tohLib.regex.match "''" "";
      expected = [ ];
    };
  };
}
