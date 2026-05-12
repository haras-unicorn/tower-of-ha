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
      options.toh.test = {
        network = {
          enable = lib.mkEnableOption "ToH test network" // {
            default = true;
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf config.toh.test.network.enable (
          let
            ip = "192.168.1.${builtins.toString (9 + config.virtualisation.test.nodeNumber)}";
          in
          {
            toh.meta.network.ip = lib.mkDefault ip;
            toh.meta.network.interface = lib.mkDefault "eth1";
            virtualisation.vlans = [ 1 ];
            # NOTE: mkBefore because we want to override the default one
            networking.interfaces.eth1.ipv4.addresses = lib.mkBefore [
              {
                address = config.toh.meta.network.ip;
                prefixLength = 24;
              }
            ];
          }
        ))
        {
          toh.cluster = tohLib.cluster.fromTestNodes nodes;

          toh.meta.machine.name = config.virtualisation.test.nodeName;
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

          virtualisation.memorySize = 8192; # in MiB
          virtualisation.cores = 4;
          virtualisation.graphics = false;
          # NOTE: needed for raft consensus so clock doesn't drift
          # requires VT‑x / AMD‑V enabled in BIOS
          virtualisation.qemu.options = [ "-cpu host,+kvmclock" ];
          boot.kernelParams = lib.mkAfter [
            "clocksource=kvm-clock"
            "clocksource_wd=0"
          ];

          # Workaround for nixpkgs gzip/install-info issue
          documentation.info.enable = false;

          system.stateVersion = config.toh.meta.machine.version;

          environment.systemPackages = [
            pkgs.curl
            pkgs.jq
            pkgs.dig
            pkgs.socat
            pkgs.helix
          ];
        }
      ];
    };
}
