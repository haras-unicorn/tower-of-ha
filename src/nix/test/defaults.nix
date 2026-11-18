{ selfLib, ... }:

{
  self.lib.test.makeNixosTest = module: {
    flake = true;

    value = _: {
      imports = [ module ] ++ (builtins.attrValues selfLib.test.testModules);
    };
  };

  self.lib.test.testModules.defaults =
    { lib, ... }:
    {
      globalTimeout = lib.mkDefault 300;

      node.pkgsReadOnly = false;

      defaults =
        { lib, ... }:
        {
          imports = [
            selfLib.nixosModules.default
          ]
          ++ (builtins.attrValues selfLib.test.nixosModules);

          # NOTE: newer ceph makes 32 byte keys and kernels before 7.0 refuse
          # them; ceph-fuse also mounts faster, so tests use it unless they
          # test the kernel client
          toh.services.cephfs.mountDriver = lib.mkDefault "fuse";

          services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
          services.openssh.settings.PasswordAuthentication = lib.mkForce true;
        };

      nodeDefaults =
        { config, lib, ... }:
        {
          # NOTE: the vm disk holds the file the ceph OSD keeps its data in,
          # on top of the 1024 MB the disk has by default
          virtualisation.diskSize = lib.mkIf config.toh.services.cephfs.enable (
            1024 + config.toh.services.cephfs.capacityInMB + 16
          );
        };

      containerDefaults =
        {
          pkgs,
          config,
          lib,
          ...
        }:
        {
          # NOTE: ceph-fuse needs /dev/fuse, which the build sandbox only has
          # when the host adds it to extra-sandbox-paths
          virtualisation.systemd-nspawn.options = lib.mkIf config.toh.services.cephfs.enable [
            "--bind=/dev/fuse"
          ];

          # NOTE: containers have no /dev/watchdog, and a watchdog bound in
          # from the host would reset the host
          toh.services.patroni.softwareWatchdog = false;

          # NOTE: containers cannot set the clock of the host, so chrony only
          # serves and tracks time there
          services.chrony.extraFlags = [ "-x" ];

          # NOTE: nixos starts sshd on demand in containers, but machines run
          # it as a daemon, and the tests should see the same units
          services.openssh.startWhenNeeded = false;

          # NOTE: ssh refuses included config files that root does not own,
          # and store files are not owned by root in the build sandbox; toh
          # does not use this proxy
          programs.ssh.systemd-ssh-proxy.enable = false;

          # NOTE: without pam, sshd refuses key logins to accounts locked
          # with a leading "!"; "*" still allows no password login
          users.users.${config.toh.meta.user.user}.hashedPassword = "*";

          # NOTE: pam does not work in the build sandbox, so tests could not
          # switch users; this is the same hack nixpkgs uses for login
          security.pam.services.su.text = ''
            auth sufficient ${pkgs.linux-pam}/lib/security/pam_permit.so
            account sufficient ${pkgs.linux-pam}/lib/security/pam_permit.so
            password sufficient ${pkgs.linux-pam}/lib/security/pam_permit.so
            session sufficient ${pkgs.linux-pam}/lib/security/pam_permit.so
          '';
        };
    };
}
