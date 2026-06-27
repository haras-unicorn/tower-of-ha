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
          package = pkgs.forgejo-runner;

          instances.forgejo = {
            enable = true;
            name = config.toh.meta.machine.name;
            url = config.toh.lib.services.endpoint.toUrl config.toh.meta.proxies.forgejo-web.endpoint { };
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

        systemd.services.gitea-runner-forgejo = {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce owner;
            Group = lib.mkForce group;
          };
        };

        toh.meta.sops.secrets."forgejo-runner-token" = {
          user = owner;
          group = group;
          mode = "0400";
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
