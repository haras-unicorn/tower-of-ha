{ lib, ... }:

{
  self.overlays.overlays.mustache = {
    deps = [ "nushell" ];
    value = final: _prev: {
      renderMustacheTemplate =
        {
          name,
          template ? null,
          templateFile ? null,
          variables ? { },
          variablesFile ? null,
        }:
        let
          finalTemplateFile = final.writeText "${name}-template" ''
            ${lib.optionalString (template != null) template}
            ${lib.optionalString (templateFile != null) (builtins.readFile templateFile)}
          '';
        in
        final.runCommand name
          ({ nativeBuildInputs = [ final.mo ]; } // (if variables != { } then { env = variables; } else { }))
          (
            if variablesFile == null then
              "mo ${lib.escapeShellArg finalTemplateFile} > $out"
            else
              ''
                env $(cat ${lib.escapeShellArg variablesFile} | xargs) \
                  mo ${lib.escapeShellArg finalTemplateFile} > $out
              ''
          );

      mustacheRenderer = final.tohPackages.writeNushellApplication {
        name = "mustache-renderer";
        runtimeInputs = [ final.mo ];
        text = builtins.readFile ./renderer.nu;
      };
    };
  };
}
