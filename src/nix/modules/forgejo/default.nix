{
  toh.lib.nixosModules.services-forgejo =
    {
      lib,
      tohLib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo;

      anyMachines = tohLib.anyServiceMachines "forgejo";

      httpPort = 3000;
      sshPort = 2222;

      proxyHttpAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo.endpoint;
      proxySshAttrs = tohLib.services.endpoint.toAttrs config.toh.meta.proxies.git.endpoint;

      forgejoCfg = config.services.forgejo;
      configFile = cfg.config.path;
      exeWithConfig = ''${lib.getExe forgejoCfg.package} --config "${configFile}"'';

      owner = "forgejo";
      group = "forgejo";
    in
    {
      options.toh.services = {
        forgejo = {
          enable = lib.mkEnableOption "Forgejo git service";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.git = {
            http = {
              host = proxyHttpAttrs.host;
              port = proxyHttpAttrs.port;
            };
            ssh = {
              host = proxySshAttrs.host;
              port = proxySshAttrs.port;
              user = owner;
            };
          };
        })
        (lib.mkIf cfg.enable {
          environment.systemPackages = [
            pkgs.forgejo-cli
            pkgs.forgejo
            pkgs.git
          ];

          services.forgejo = {
            enable = true;
            package = pkgs.forgejo-lts;
            user = owner;
            group = group;

            # NOTE: might seem weird but this just means
            # were the ones managing secrets and not nixpkgs
            useWizard = true;
          };

          systemd.services.forgejo = {
            preStart = lib.mkForce ''
              ${exeWithConfig} admin regenerate hooks
              if [ -r ${forgejoCfg.stateDir}/.ssh/authorized_keys ]; then
                ${exeWithConfig} admin regenerate keys
              fi
            '';
            environment = {
              HOME = forgejoCfg.stateDir;
            };
            serviceConfig = {
              ExecStart = lib.mkForce ''
                ${exeWithConfig} web --pid /run/forgejo/forgejo.pid
              '';
              LoadCredential = lib.mkForce [ ];
            };
          };

          systemd.targets.toh-git-online = {
            wantedBy = [ "forgejo.service" ];
            bindsTo = [ "forgejo.service" ];
            after = [ "forgejo.service" ];
          };

          networking.firewall.allowedTCPPorts = [
            httpPort
            sshPort
          ];

          toh.meta.services.forgejo = {
            endpoint.http = {
              port = httpPort;
            };
            health.endpoint.http = {
              port = httpPort;
              path = "/api/healthz";
            };
          };

          toh.meta.services.git = {
            endpoint.tcp = {
              port = sshPort;
              sslTermination = "passthrough";
            };
            health.endpoint.tcp = {
              port = sshPort;
              packets = [
                {
                  send = null;
                  expect = "SSH";
                }
              ];
            };
          };

          toh.services.forgejo.createUserGroup = true;
        })
      ];
    };
}
