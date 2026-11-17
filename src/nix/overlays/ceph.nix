{
  toh.overlays.ceph = {
    nixos = true;
    value = final: prev: {
      ceph =
        (prev.ceph.overrideScope (
          scopeFinal: scopePrev: {
            ceph-python-env = scopePrev.ceph-python-env.override (old: {
              extraLibs = old.extraLibs ++ [ scopeFinal.ceph-python.pkgs.distro ];
            });
          }
        )).ceph;
    };
  };
}
