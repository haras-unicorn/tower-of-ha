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
  self.overlays.overlays.samba-ctdb = {
    value = final: prev: {
      sambaCtdb = prev.samba.overrideAttrs (overrideAttrs final);
      samba4FullCtdb = prev.samba4Full.overrideAttrs (overrideAttrs final);
    };
  };
}
