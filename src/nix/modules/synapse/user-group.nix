{
  self.nixosModules.services-synapse-user-group.flake = true;
  self.nixosModules.services-synapse-user-group.value =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.synapse;

      name = "matrix-synapse";
      owner = name;
      group = name;
    in
    {
      options.toh.services = {
        synapse = {
          createUserGroup = lib.mkEnableOption "synapse user and group creation";
        };
      };

      config = lib.mkIf cfg.createUserGroup {
        users.groups.${group} = { };

        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };
      };
    };
}
