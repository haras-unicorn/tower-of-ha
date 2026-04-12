{
  libAttrs.test.nixosModules.host =
    {
      lib,
      config,
      nodes,
      pkgs,
      ...
    }:
    {
      options.toh.test = {
        network = {
          enable = lib.mkEnableOption "Test network";
        };
      };

      config = lib.mkMerge [
        ({ toh.test.network.enable = lib.mkDefault true; })
        (lib.mkIf config.toh.test.network.enable (
          let
            ip = "192.168.1.${builtins.toString (9 + config.virtualisation.test.nodeNumber)}";
          in
          {
            toh.host.ip = lib.mkDefault ip;
            toh.host.interface = lib.mkDefault "eth1";
            virtualisation.vlans = [ 1 ];
            # NOTE: mkBefore because we want to override the default one
            networking.interfaces.eth1.ipv4.addresses = lib.mkBefore [
              {
                address = config.toh.host.ip;
                prefixLength = 24;
              }
            ];
          }
        ))
        {
          toh.host.user = "haras";
          toh.host.group = "haras";
          toh.host.uid = 1000;
          toh.host.gid = 1000;
          toh.host.home = "/home/haras";
          toh.host.pass = lib.mkDefault true;
          toh.host.version = "24.11";
          users.groups.${config.toh.host.group} = {
            gid = config.toh.host.gid;
          };
          users.users.${config.toh.host.user} = {
            uid = config.toh.host.uid;
            group = config.toh.host.group;
            isNormalUser = true;
            home = config.toh.host.home;
            createHome = true;
          };

          toh.host.name = config.virtualisation.test.nodeName;
          toh.host.hosts = builtins.map (
            node:
            node.toh.host
            // {
              system = node;
            }
          ) (builtins.attrValues nodes);

          networking.hostName = config.toh.host.name;

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

          system.stateVersion = config.toh.host.version;

          environment.systemPackages = [
            pkgs.curl
            pkgs.jq
            pkgs.dig
          ];
        }
      ];
    };
}
