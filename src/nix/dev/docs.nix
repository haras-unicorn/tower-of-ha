{ self, ... }:

{
  perSystem =
    { pkgs, ... }:
    {
      packages.docs = pkgs.harasPackages.mkMdbook {
        src = self;
      };
    };
}
