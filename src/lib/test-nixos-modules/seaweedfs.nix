{ self, ... }:

{
  libAttrs.test.nixosModules.seaweedfs =
    { lib, config, ... }:
    {
      imports = [
        self.nixosModules.services-seaweedfs
        self.nixosModules.services-seaweedfs-nixpkgs-servers
        self.nixosModules.services-seaweedfs-nixpkgs-clients
        self.nixosModules.services-seaweedfs-nixpkgs-master
        self.nixosModules.services-seaweedfs-nixpkgs-volumes
        self.nixosModules.services-seaweedfs-nixpkgs-filers
        self.nixosModules.services-seaweedfs-nixpkgs-mounts
        self.nixosModules.services-seaweedfs-backup
      ];

      options.toh.test = {
        seaweedfs = {
          enable = lib.mkEnableOption "SeaweedFS test";
        };
      };

      config = lib.mkIf config.toh.test.seaweedfs.enable {
        toh.seaweedfs.enable = true;
      };
    };
}
