{ selfLib, lib, ... }:

{
  self.lib.regex = {
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
      if selfLib.regex.isRegex regexOrString then
        builtins.match (selfLib.regex.unwrapRegex regexOrString) string
      else if (selfLib.regex.unwrapString regexOrString) == string then
        [ ]
      else
        null;
  };

  self.unitTests.regex = {
    test-is-regex-unwrapped = {
      expr = selfLib.regex.isRegex "not a regex";
      expected = false;
    };
    test-is-regex-wrapped = {
      expr = selfLib.regex.isRegex "/a regex/";
      expected = true;
    };
    test-is-regex-only-start = {
      expr = selfLib.regex.isRegex "/not a regex";
      expected = false;
    };
    test-is-regex-only-end = {
      expr = selfLib.regex.isRegex "not a regex/";
      expected = false;
    };
    test-unwrap-regex-wrapped = {
      expr = selfLib.regex.unwrapRegex "/a regex/";
      expected = "a regex";
    };
    test-unwrap-regex-wrapped-twice = {
      expr = selfLib.regex.unwrapRegex "//a regex//";
      expected = "/a regex/";
    };
    test-unwrap-regex-empty = {
      expr = selfLib.regex.unwrapRegex "//";
      expected = "";
    };
    test-unwrap-string-wrapped = {
      expr = selfLib.regex.unwrapString "'not a regex'";
      expected = "not a regex";
    };
    test-unwrap-string-wrapped-twice = {
      expr = selfLib.regex.unwrapString "''not a regex''";
      expected = "'not a regex'";
    };
    test-unwrap-string-empty = {
      expr = selfLib.regex.unwrapString "''";
      expected = "";
    };
    test-match-regex-matches = {
      expr = selfLib.regex.match "/a .*/" "a regex";
      expected = [ ];
    };
    test-match-regex-does-not-match = {
      expr = selfLib.regex.match "/a .*/" "regex";
      expected = null;
    };
    test-match-regex-empty = {
      expr = selfLib.regex.match "//" "";
      expected = [ ];
    };
    test-match-regex-groups = {
      expr = selfLib.regex.match "/(a)(b)c/" "abc";
      expected = [
        "a"
        "b"
      ];
    };
    test-match-string-matches-unwrapped = {
      expr = selfLib.regex.match "not a regex" "not a regex";
      expected = [ ];
    };
    test-match-string-does-not-match-unwrapped = {
      expr = selfLib.regex.match "not a regex" "a regex";
      expected = null;
    };
    test-match-string-matches-wrapped = {
      expr = selfLib.regex.match "'not a regex'" "not a regex";
      expected = [ ];
    };
    test-match-string-does-not-match-wrapped = {
      expr = selfLib.regex.match "'not a regex'" "a regex";
      expected = null;
    };
    test-match-string-matches-wrapped-slashes = {
      expr = selfLib.regex.match "'/not a regex/'" "/not a regex/";
      expected = [ ];
    };
    test-match-string-matches-unwrapped-empty = {
      expr = selfLib.regex.match "" "";
      expected = [ ];
    };
    test-match-string-matches-wrapped-empty = {
      expr = selfLib.regex.match "''" "";
      expected = [ ];
    };
  };
}
