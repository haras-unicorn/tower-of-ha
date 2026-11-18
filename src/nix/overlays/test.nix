{ selfLib, ... }:

{
  self.overlays.overlays.test = {
    value = final: _prev: {
      testers.runToHTest =
        module:
        final.testers.runNixOSTest {
          imports = [ module ] ++ (builtins.attrValues selfLib.test.testModules);
        };
    };
  };
}
