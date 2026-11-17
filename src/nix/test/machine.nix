{
  toh.lib.test.nixosModules.machine =
    {
      lib,
      tohLib,
      config,
      nodes,
      pkgs,
      ...
    }:
    {
      toh.meta.cluster = tohLib.cluster.fromTestNodes nodes;

      toh.meta.machine.name = config.virtualisation.test.nodeName;
      toh.meta.machine.index = config.virtualisation.test.nodeNumber;
      toh.meta.machine.version = "25.11";

      toh.meta.user.user = "test";
      toh.meta.user.group = "test";
      toh.meta.user.uid = 1000;
      toh.meta.user.gid = 1000;
      toh.meta.user.home = "/home/test";
      toh.meta.user.generatedPassword = lib.mkDefault true;

      users.groups.${config.toh.meta.user.group} = {
        gid = config.toh.meta.user.gid;
      };
      users.users.${config.toh.meta.user.user} = {
        uid = config.toh.meta.user.uid;
        group = config.toh.meta.user.group;
        isNormalUser = true;
        home = config.toh.meta.user.home;
        createHome = true;
      };

      networking.hostName = config.toh.meta.machine.name;

      virtualisation.memorySize = 8192; # 8 GiB
      virtualisation.cores = 4;
      virtualisation.graphics = false;
      # NOTE: needed for raft consensus so clock doesn't drift
      # requires VT‑x / AMD‑V enabled in BIOS
      virtualisation.qemu.options = [ "-cpu host,+kvmclock" ];
      boot.kernelParams = lib.mkAfter [
        "clocksource=kvm-clock"
        "tsc=nowatchdog"
      ];

      # Workaround for nixpkgs gzip/install-info issue
      documentation.info.enable = false;

      system.stateVersion = config.toh.meta.machine.version;

      environment.variables = {
        PAGER = "cat";
      };

      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
        pkgs.dig
        pkgs.socat
        pkgs.helix
        pkgs.nushell
        pkgs.usql
      ];
    };
}
