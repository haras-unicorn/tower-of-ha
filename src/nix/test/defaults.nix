{ selfLib, ... }:

{
  self.lib.test.makeNixosTest = module: {
    flake = true;

    value = _: {
      imports = [ module ] ++ (builtins.attrValues selfLib.test.testModules);
    };
  };

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

    # NOTE: containers have no /dev/watchdog, and a watchdog bound in from
    # the host would reset the host
    containerDefaults.toh.services.patroni.softwareWatchdog = false;
  };
}
