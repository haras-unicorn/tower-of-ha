{
  lib,
  tohLib,
  ...
}:

{
  toh.lib.cli.makeOverlay = tohLib.cli.makeOverrideOverlay "cli";

  toh.lib.cli.makeOverrideOverlay =
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
      deps = [
        "packages"
        "${attr}-package"
      ]
      ++ deps;
      value = final: prev: {
        tohPackages = prev.tohPackages // {
          ${attr} = prev.tohPackages.${attr}.override (
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
                  builtins.readFile (
                    final.tohPackages.renderMustacheTemplate {
                      name = "toh-${attr}-rendered-extra-text";
                      variables = extraTextVariables;
                      template = newExtraText;
                    }
                  );

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
    };

  toh.lib.cli.makeBaseOverlay = attr: {
    deps = [
      "packages"
      "nushell"
      "mustache"
    ];
    value = final: prev: {
      tohPackages = prev.tohPackages // {
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
  };

  toh.lib.cli.makeFinalOverlay = attr: {
    deps = [ "${attr}-.*" ];
    flake = true;
    nixos = true;
    value = final: prev: { };
  };
}
