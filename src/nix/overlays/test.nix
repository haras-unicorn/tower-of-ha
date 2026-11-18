{ selfLib, ... }:

{
  self.overlays.overlays.test = {
    value = final: _prev: {
      testers.runToHTest =
        module:
        let
          mkTest =
            { withSshBackdoor }:
            final.testers.runNixOSTest {
              imports = [ module ] ++ (builtins.attrValues selfLib.test.testModules);
              sshBackdoor.enable = withSshBackdoor;
            };

          original = mkTest { withSshBackdoor = false; };

          withSshBackdoor = mkTest { withSshBackdoor = true; };
        in
        original // { inherit withSshBackdoor; };
    };
  };
}
