{
  toh.lib.nixosModules.services-forgejo-group =
    { lib, config, ... }:
    let
      cfg = config.toh.services.forgejo;

      name = "forgejo-config";
      group = name;
    in
    {
      options.toh.services = {
        forgejo = {
          createGroup = lib.mkEnableOption "common forgejo group creation";
        };
      };

      config = lib.mkIf cfg.createGroup {
        users.groups.${group} = { };
      };
    };
}
