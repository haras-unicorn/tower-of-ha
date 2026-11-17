{
  self.nixosModules.meta-locality.flake = true;
  self.nixosModules.meta-locality.value =
    { lib, ... }:
    {
      options.toh.meta = {
        locality = {
          region = lib.mkOption {
            type = lib.types.str;
            default = "origin";
            description = ''
              Machine region.
            '';
          };

          dataCenter = lib.mkOption {
            type = lib.types.str;
            default = "homelab";
            description = ''
              Machine data center.
            '';
          };

          rack = lib.mkOption {
            type = lib.types.str;
            default = "shelf";
            description = ''
              Machine rack.
            '';
          };
        };
      };
    };
}
