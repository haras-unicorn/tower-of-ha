{ self, ... }:

{
  libAttrs.test.nixosModules.openssl =
    { lib, config, ... }:
    {
      imports = [
        self.nixosModules.services-openssl
        self.nixosModules.services-openssl-nixpkgs
      ];

      options.toh.test = {
        openssl = {
          enable = lib.mkEnableOption "openssl test";
        };
      };

      config = lib.mkIf config.toh.test.openssl.enable {
        toh.openssl.enable = true;
      };
    };
}
