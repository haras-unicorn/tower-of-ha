{ lib, ... }:

# NOTE: the helpers call each other through this let and not through selfLib,
# because flake-level overlays are made with them and selfLib depends on every
# overlay through the flake assertions of haraspkgs

let
  makeOverrideOverlay =
    attr:
    {
      name ? null,
      deps ? [ ],
      extraRuntimeInputs ? [ ],
      extraText ? "",
      extraTextFile ? null,
      extraTextDir ? null,
      extraTextVariables ? null,
    }:
    let
      fileText = if extraTextFile == null then "" else builtins.readFile extraTextFile;

      dirText =
        if extraTextDir == null then
          ""
        else
          builtins.concatStringsSep "\n\n" (
            builtins.map (script: builtins.readFile (lib.path.append extraTextDir script)) (
              builtins.filter (lib.hasSuffix ".nu") (builtins.attrNames (builtins.readDir extraTextDir))
            )
          );
    in
    {
      deps = [ "${attr}-package" ] ++ deps;
      value = final: prev: {
        ${attr} = prev.${attr}.override (
          prev:
          let
            nextName = if name == null then prev.name else name;

            nextExtraRuntimeInputs =
              prev.extraRuntimeInputs
              ++ (if lib.isFunction extraRuntimeInputs then extraRuntimeInputs final else extraRuntimeInputs);

            newExtraText = builtins.concatStringsSep "\n\n" [
              extraText
              fileText
              dirText
            ];

            renderedNewExtraText =
              if extraTextVariables == null then
                newExtraText
              else
                final.harasPackages.renderMustacheText {
                  name = "toh-${attr}-rendered-extra-text";
                  text = newExtraText;
                  vars = extraTextVariables;
                };

            nextExtraText = prev.extraText + "\n\n" + renderedNewExtraText;
          in
          {
            name = nextName;
            extraRuntimeInputs = nextExtraRuntimeInputs;
            extraText = nextExtraText;
          }
        );
      };
    };

  makeBaseOverlay = attr: {
    deps = [
      "nushell"
      "mustache"
    ];
    value = final: _prev: {
      ${attr} =
        final.callPackage
          (
            {
              name,
              extraRuntimeInputs,
              extraText,
              tohPackages,
            }:
            tohPackages.writeNushellApplication {
              inherit name;
              runtimeInputs = [ final.nushell ] ++ extraRuntimeInputs;
              text = ''
                def "toh name" [] {
                  "${name}"
                }

                def "toh file" [] {
                  $"($env.FILE_PWD)/(toh name)"
                }

                ${extraText}
              '';
            }
          )
          {
            name = attr;
            extraRuntimeInputs = [ ];
            extraText = "";
          };
    };
  };

  makeFinalOverlay = attr: {
    deps = [ "/${attr}-.*/" ];
    value =
      _final: prev:
      assert lib.assertMsg (prev ? ${attr}) "Missing ToH package ${attr}";
      { };
  };

  makeOverlays =
    {
      name,
      attr ? name,
      deps ? [ ],
      runtimeInputs ? [ ],
      text ? "",
      textFile ? null,
      textDir ? null,
      textVariables ? null,
    }:
    {
      "${attr}-package" = makeBaseOverlay "${attr}";
      "${attr}" = makeFinalOverlay "${attr}";
      "${attr}-impl" = makeOverrideOverlay "${attr}" {
        inherit name deps;
        extraRuntimeInputs = runtimeInputs;
        extraText = text;
        extraTextFile = textFile;
        extraTextDir = textDir;
        extraTextVariables = textVariables;
      };
    };
in
{
  self.lib.cli = {
    makeOverlay = makeOverrideOverlay "cli";

    inherit
      makeOverlays
      makeOverrideOverlay
      makeBaseOverlay
      makeFinalOverlay
      ;
  };
}
