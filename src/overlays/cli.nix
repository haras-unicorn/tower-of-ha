{ lib, ... }:

{
  libAttrs.cli.makeOverlay =
    {
      extraRuntimeInputs ? (_: [ ]),
      extraText ? "",
    }:
    final: prev: {
      tohPackages = (prev.tohPackages or { }) // {
        cli = prev.tohPackages.cli.override (prev: {
          extraRuntimeInputs = prev.extraRuntimeInputs ++ (extraRuntimeInputs final);
          extraText = prev.extraText + extraText;
        });
      };
    };

  overlayList = lib.mkBefore [
    {
      name = "cli";
      value = final: prev: {
        tohPackages = (prev.tohPackages or { }) // {
          cli =
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
                    def main [] {
                      exec nu -c $"($env.FILE_PWD)/${name} --help"
                    }

                    ${extraText}
                  '';
                }
              )
              {
                name = "toh";
                extraRuntimeInputs = [ ];
                extraText = "";
              };
        };
      };
    }
  ];
}
