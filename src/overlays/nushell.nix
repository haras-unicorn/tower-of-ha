{
  toh.overlays.nushell = {
    deps = [ "packages" ];
    nixos = true;
    value = final: prev: {
      tohPackages = prev.tohPackages // {
        writeNushellApplication =
          {
            name,
            runtimeInputs ? [ ],
            text ? "",
          }:
          let
            pkgs = final;

            path = builtins.concatStringsSep "\n  " (builtins.map (input: "`${input}/bin`") runtimeInputs);

            wrapped = pkgs.writeText "${name}-wrapped.nu" ''
              #!${pkgs.lib.getExe pkgs.nushell}

              $env.PATH ++= [
                ${path}
              ]

              ${text}
            '';
          in
          pkgs.runCommand name
            {
              nativeBuildInputs = [ pkgs.nushell ];
              meta.mainProgram = name;
            }
            ''
              nu --commands "nu-check --debug ${wrapped}"
              mkdir -p $out/bin
              cp ${wrapped} $out/bin/${name}
              chmod +x $out/bin/${name}
            '';
      };
    };
  };
}
