{ inputs, lib, ... }:

let
  applyNixpkgsPatches =
    pkgs:
    { src, ... }@attrs:
    let
      patchedNixpkgs = pkgs.applyPatches (
        attrs
        // {
          inherit src;
          patches =
            (attrs.patches or [ ])
            ++ builtins.map (name: lib.path.append ./. name) (
              builtins.attrNames (
                lib.filterAttrs (name: type: type == "regular" && (lib.hasSuffix ".patch" name)) (
                  builtins.readDir ./.
                )
              )
            );
        }
        // (if attrs ? name then { name = "${attrs.name}-with-toh-patches"; } else { })
      );
    in
    patchedNixpkgs;
in
{
  toh.overlays.apply-patches = {
    value = final: prev: {
      applyTohNixpkgsPatches = attrs: applyNixpkgsPatches final attrs;
    };
  };

  perSystem =
    {
      system,
      lib,
      tohLib,
      ...
    }:
    let
      originalPkgs = import inputs.nixpkgs {
        inherit system;
      };

      nixpkgs = applyNixpkgsPatches originalPkgs {
        name = "nixpkgs";
        src = originalPkgs.path;
      };
    in
    {
      _module.args.pkgs = (
        import nixpkgs {
          inherit system;
          overlays = [ tohLib.overlays.default ];
          config = {
            allowUnfree = true;
          };
        }
      );
    };
}
