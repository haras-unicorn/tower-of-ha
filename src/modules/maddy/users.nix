{
  toh.lib.nixosModules.services-maddy-users =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    {
      config = {
        toh.overlays.cli-maddy = tohLib.cli.makeOverlay {
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
