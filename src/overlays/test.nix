{ tohLib, ... }:

{
  toh.overlays.test = {
    deps = [ "packages" ];
    value = final: prev: {
      tohPackages = prev.tohPackages // {
        testers.runToHTest =
          module:
          let
            mkTest =
              { withSshBackdoor }:
              final.testers.runNixOSTest {
                imports = [ module ] ++ (builtins.attrValues tohLib.test.testModules);
                sshBackdoor.enable = withSshBackdoor;
                node.pkgsReadOnly = false;
                defaults =
                  { lib, ... }:
                  {
                    imports =
                      (builtins.attrValues tohLib.nixosModules) ++ (builtins.attrValues tohLib.test.nixosModules);

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
