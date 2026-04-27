{ self, ... }:

{
  libAttrs.test.nixosModules.cockroachdb =
    { lib, config, ... }:
    {
      imports = [
        self.nixosModules.services-cockroachdb
        self.nixosModules.services-cockroachdb-nixpkgs
        self.nixosModules.services-cockroachdb-apps
        self.nixosModules.services-cockroachdb-root
        self.nixosModules.services-cockroachdb-user
        self.nixosModules.services-cockroachdb-backup
        self.nixosModules.services-cockroachdb-builtin-backup
        self.nixosModules.services-cockroachdb-user-group
        self.nixosModules.services-cockroachdb-ca
      ];

      options.toh.test = {
        cockroachdb = {
          enable = lib.mkEnableOption "CockroachDB test";
        };
      };

      config = lib.mkIf config.toh.test.cockroachdb.enable {
        toh.cockroachdb.enable = true;
      };
    };
}
