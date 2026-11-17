{ lib, tohLib, ... }:

{
  toh.lib.types = {
    overlay = lib.types.submodule (
      { name, ... }:
      {
        options = {
          deps = lib.mkOption {
            type = lib.types.listOf tohLib.types.regexOrString;
            default = [ ];
            description = "Dependencies of this overlay for composition";
          };
          nixos = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this overlay should be exported as a flake overlay";
          };
          flake = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this overlay should be exported as a nixos overlay";
          };
          value = lib.mkOption {
            type = lib.types.functionTo (lib.types.functionTo lib.types.raw);
            description = "Overlay value";
          };
        };
      }
    );
  };

  toh.lib.overlay = {
    transitiveDeps =
      allOverlays: name:
      let
        go =
          current: visited:
          assert lib.assertMsg (!(builtins.elem current visited)) (
            let
              cycle = builtins.concatStringsSep " -> " (visited ++ [ current ]);
            in
            "Cycle in overlays: ${cycle} with loop: ${current}"
          );
          let
            directDeps = allOverlays.${current}.deps or [ ];

            deps = builtins.filter (
              overlay: builtins.any (dep: (tohLib.regex.match dep overlay) != null) directDeps
            ) (builtins.attrNames allOverlays);
          in
          lib.unique (deps ++ lib.concatMap (dep: go dep (visited ++ [ current ])) deps);
      in
      go name [ ];

    composeOverlay =
      allOverlays: overlays:
      let
        overlayNames = lib.unique (
          (builtins.attrNames overlays)
          ++ (builtins.concatMap (tohLib.overlay.transitiveDeps allOverlays) (builtins.attrNames overlays))
        );

        namedOverlays = builtins.map (name: { inherit name; } // allOverlays.${name}) overlayNames;

        sorted = lib.toposort (
          a: b: builtins.any (dep: (tohLib.regex.match dep a.name) != null) b.deps
        ) namedOverlays;
      in
      assert lib.assertMsg (sorted ? result) (
        let
          cycle = builtins.concatStringsSep " -> " (builtins.map ({ name, ... }: name) overlays);
          loops = builtins.toString (builtins.deepSeq sorted.loops);
        in
        "Cycle in overlays: ${cycle} with loops: ${loops}"
      );
      lib.composeManyExtensions (builtins.map ({ value, ... }: value) sorted.result);

    composeOverlayAttrs =
      allOverlays: overlays:
      builtins.mapAttrs (
        current: overlay:
        tohLib.overlay.composeOverlay (
          {
            ${current} = overlay;
          }
          // (lib.filterAttrs (
            name: _: builtins.elem name (tohLib.overlay.transitiveDeps current)
          ) allOverlays)
        )
      ) overlays;

    makeUndefinedDepsAssertion =
      overlays:
      let
        allOverlayNames = builtins.attrNames overlays;
        undefinedDepsPerOverlay = builtins.mapAttrs (
          _:
          { deps, ... }:
          builtins.filter (
            dep: !builtins.any (overlay: (tohLib.regex.match dep overlay) != null) allOverlayNames
          ) deps
        ) overlays;
        undefinedDepsString = builtins.concatStringsSep "; " (
          lib.mapAttrsToList (
            name: value: "${builtins.concatStringsSep ", " value} -> ${name}"
          ) undefinedDepsPerOverlay
        );
      in
      {
        assertion = builtins.all (deps: deps == [ ]) (builtins.attrValues undefinedDepsPerOverlay);
        message = "Dependencies ${undefinedDepsString} of overlays are undefined";
      };
  };

  flake.tests.overlays =
    let
      testOverlays = {
        base = {
          deps = [ ];
          flake = false;
          nixos = false;
          value = final: prev: { base = "base"; };
        };
        a = {
          deps = [ "base" ];
          flake = false;
          nixos = false;
          value = final: prev: { a = prev.base + "-a"; };
        };
        b = {
          deps = [ "base" ];
          flake = false;
          nixos = false;
          value = final: prev: { b = prev.base + "-b"; };
        };
        c = {
          deps = [
            "a"
            "b"
          ];
          flake = false;
          nixos = false;
          value = final: prev: { c = prev.a + "-" + prev.b; };
        };
        d = {
          deps = [ "/a|b/" ];
          flake = false;
          nixos = false;
          value = final: prev: { d = prev.a + "-" + prev.b; };
        };
        exportOnly = {
          deps = [ ];
          flake = true;
          nixos = true;
          value = final: prev: { exportOnly = "export"; };
        };
        exportWithDep = {
          deps = [ "base" ];
          flake = true;
          nixos = true;
          value = final: prev: { exportDep = prev.base + "-export"; };
        };
        final = {
          deps = [ "c" ];
          flake = false;
          nixos = false;
          value = final: prev: { final = "final-" + prev.c; };
        };
        transitive-regex = {
          deps = [ "d" ];
          flake = false;
          nixos = false;
          value = final: prev: { final = "final-" + prev.d; };
        };
      };

      composed = tohLib.overlay.composeOverlay testOverlays testOverlays;

      result = composed { } { };

      flakeComposed = tohLib.overlay.composeOverlay testOverlays (
        lib.filterAttrs (_: { flake, ... }: flake) testOverlays
      );

      flakeResult = flakeComposed { } { };
    in
    {
      test-base = {
        expr = result.base;
        expected = "base";
      };

      test-linear-chain = {
        expr = result.a;
        expected = "base-a";
      };

      test-diamond = {
        expr = result.c;
        expected = "base-a-base-b";
      };

      test-regex = {
        expr = result.d;
        expected = "base-a-base-b";
      };

      test-composed-default = {
        expr = result.final;
        expected = "final-base-a-base-b";
      };

      test-flake-overlays-are-separate = {
        expr = flakeResult.exportOnly;
        expected = "export";
      };

      test-flake-overlay-with-dep = {
        expr = flakeResult.exportDep;
        expected = "base-export";
      };

      test-transitive-deps = {
        expr = tohLib.overlay.transitiveDeps testOverlays "final";
        expected = [
          "c"
          "a"
          "b"
          "base"
        ];
      };

      test-transitive-regex = {
        expr = tohLib.overlay.transitiveDeps testOverlays "transitive-regex";
        expected = [
          "d"
          "a"
          "b"
          "base"
        ];
      };

      test-empty-transitive-deps = {
        expr = tohLib.overlay.transitiveDeps testOverlays "base";
        expected = [ ];
      };
    };
}
