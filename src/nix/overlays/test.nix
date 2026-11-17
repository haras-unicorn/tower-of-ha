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
              node.pkgsReadOnly = false;
              defaults =
                { lib, ... }:
                {
                  imports = [
                    selfLib.nixosModules.default
                  ]
                  ++ (builtins.attrValues selfLib.test.nixosModules);

                  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
                  services.openssh.settings.PasswordAuthentication = lib.mkForce true;
                };
            };

          original = mkTest { withSshBackdoor = false; };

          withSshBackdoor = mkTest { withSshBackdoor = true; };
        in
        original // { inherit withSshBackdoor; };
    };
  };
}
