let
  overrideAttrs = pkgs: prev: {
    patches = (prev.patches or [ ]) ++ [
      ./4.x-no-persistent-install.patch
    ];
    wafConfigureFlags = (prev.wafConfigureFlags or [ ]) ++ [ "--with-cluster-support" ];
    postPatch = (prev.postPatch or "") + ''
      patchShebangs .
    '';
  };
in
{
  toh.overlays.samba-ctdb = {
    deps = [ "packages" ];
    nixos = true;
    value = final: prev: {
      tohPackages = prev.tohPackages // {
        sambaCtdb = prev.samba.overrideAttrs (overrideAttrs final);
        samba4FullCtdb = prev.samba4Full.overrideAttrs (overrideAttrs final);
      };
    };
  };
}
