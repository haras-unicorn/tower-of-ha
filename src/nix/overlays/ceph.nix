{
  self.overlays.overlays.ceph = {
    value = _final: prev: {
      ceph =
        (prev.ceph.overrideScope (
          _scopeFinal: scopePrev: {
            # NOTE: ceph-python-env calls ceph-python.withPackages with a fixed
            # package list, so the only way to add distro without copying the
            # list is to wrap the withPackages of the python it gets
            ceph-python-env = scopePrev.ceph-python-env.override (args: {
              ceph-python = args.ceph-python // {
                withPackages =
                  selectPackages:
                  args.ceph-python.withPackages (
                    pythonPackages: selectPackages pythonPackages ++ [ pythonPackages.distro ]
                  );
              };
            });
          }
        )).ceph;
    };
  };
}
