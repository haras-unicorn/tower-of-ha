{ lib, self, ... }:

{
  overlayList = lib.mkOrder 0 [
    {
      name = "test";
      value = final: prev: {
        tohPackages = (prev.tohPackages or { }) // {
          testers = (prev.tohPackages.testers or { }) // {
            runToHTest =
              module:
              let
                mkTest =
                  { withSshBackdoor }:
                  final.testers.runNixOSTest {
                    imports = [ module ] ++ (builtins.attrValues self.lib.test.modules);
                    sshBackdoor.enable = withSshBackdoor;
                    defaults =
                      { lib, ... }:
                      {
                        imports =
                          (builtins.attrValues (
                            lib.filterAttrs (name: _: lib.hasPrefix "capabilities" name) self.nixosModules
                          ))
                          ++ (builtins.attrValues self.lib.test.nixosModules);

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
      };
    }
  ];
}
