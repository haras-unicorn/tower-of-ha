{ selfLib, ... }:

{
  self.nixosModules.services-maddy-users.flake = true;
  self.nixosModules.services-maddy-users.value =
    {
      lib,
      config,
      ...
    }:
    {
      config = {
        toh.overlays.cli-maddy = selfLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [
            pkgs.himalaya
          ];
          extraTextFile = ./users.nu;
          extraTextVariables = {
            TOH_MADDY_USERS = builtins.toJSON config.toh.meta.ldap.users;
          };
        };
      };
    };
}
