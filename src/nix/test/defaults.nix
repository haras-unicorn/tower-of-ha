{ selfLib, ... }:

{
  self.lib.test.testModules.defaults = {
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
}
