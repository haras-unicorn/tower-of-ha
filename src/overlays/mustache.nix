{ lib, ... }:

{
  toh.overlays.mustache = {
    deps = [ "packages" ];
    value = final: prev: {
      tohPackages = prev.tohPackages // {
        renderMustacheTemplate =
          {
            name,
            template,
            templateFile ? final.writeText "${name}-template" template,
            variables,
            variablesFile ? null,
          }:
          final.runCommand name
            {
              env = variables;
              nativeBuildInputs = [ final.mo ];
            }
            (
              if variablesFile == null then
                "mo ${lib.escapeShellArg templateFile} > $out"
              else
                ''
                  env $(cat ${lib.escapeShellArg variablesFile} | xargs) \
                    mo ${lib.escapeShellArg templateFile} > $out
                ''
            );
      };
    };
  };
}
