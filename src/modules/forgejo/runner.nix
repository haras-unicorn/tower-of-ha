{
  toh.lib.nixosModules.services-forgejo-runner =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.forgejo.runner;

      proxyHttpAttrs = config.toh.lib.services.endpoint.toAttrs config.toh.meta.proxies.forgejo-http.endpoint;

      owner = "forgejo-runner";
      group = "forgejo-runner";
    in
    {
      options.toh.services.forgejo = {
        runner = {
          enable = lib.mkEnableOption "Forgejo Actions runner";
        };
      };

      config = lib.mkIf cfg.enable {
        services.gitea-actions-runner = {
          package = pkgs.forgejo-actions-runner;

          instances.forgejo = {
            enable = true;
            name = config.toh.meta.machine.name;
            url = "https://${proxyHttpAttrs.host}";
            tokenFile = config.toh.meta.sops.secrets."forgejo-runner-token".path;
            labels = [ "self-hosted:host" ];
            hostPackages = with pkgs; [
              bash
              coreutils
              curl
              gawk
              git
              git-lfs
              gnused
              nodejs
              wget
            ];
          };
        };

        toh.meta.sops.secrets."forgejo-runner-token" = {
          user = owner;
          group = group;
          key = "forgejo-runner-token";
          mode = "0400";
          path = "/etc/forgejo-runner/token";
          restartUnits = [ "gitea-runner-forgejo.service" ];
        };

        users.groups.${group} = { };
        users.users.${owner} = {
          group = group;
          isSystemUser = true;
        };

        toh.meta.cryl.machine = [
          {
            forgejo-runner = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/forgejo-runner-token";
                    to = "forgejo-runner-token";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
