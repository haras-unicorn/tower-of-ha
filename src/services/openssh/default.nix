{ self, ... }:

# TODO: only allow from network

{
  overlayList = [
    {
      name = "cli-openssh";
      value = self.lib.cli.makeOverlay {
        extraRuntimeInputs = pkgs: [ pkgs.openssh ];
        extraText = builtins.readFile ./cli.nu;
      };
    }
  ];

  flake.nixosModules.services-openssh =
    { lib, config, ... }:
    let
      user = config.toh.host.user;
      hostname = config.toh.host.name;
      hosts = config.toh.host.hosts;
    in
    {
      config = {
        services.openssh.enable = true;
        services.openssh.allowSFTP = true;
        services.openssh.settings.PermitRootLogin = "no";
        services.openssh.settings.PasswordAuthentication = false;
        services.openssh.settings.KbdInteractiveAuthentication = false;
        services.openssh.settings.AddressFamily = "inet";
        services.openssh.settings.HostKey = "/etc/ssh/ssh_host_toh";
        # NOTE: a bit hacky but the "official" options are too static
        services.openssh.authorizedKeysFiles = [ "%h/.ssh/toh_authorized_keys" ];

        # NOTE: a bit hacky but the "official" options are too static
        programs.ssh.extraConfig = ''
          AddressFamily inet
          UserKnownHostsFile %d/.ssh/known_hosts %d/.ssh/known_hosts2 %d/.ssh/toh_known_hosts
        '';

        # NOTE: otherwise sops leaves .ssh owner root
        systemd.tmpfiles.rules = [
          "d ${config.toh.host.home}/.ssh 0700 ${user} ${user} - -"
        ];
        # NOTE: a bit hacky but the "official" options are too static
        sops.secrets."ssh-authorized-keys" = {
          path = "${config.toh.host.home}/.ssh/toh_authorized_keys";
          owner = user;
          group = user;
          mode = "0644";
        };
        # NOTE: a bit hacky but the "official" options are too static
        sops.secrets."ssh-known-hosts" = {
          path = "${config.toh.host.home}/.ssh/toh_known_hosts";
          owner = user;
          group = user;
          mode = "0644";
        };
        sops.secrets."ssh-public" = {
          path = "${config.toh.host.home}/.ssh/toh.pub";
          owner = user;
          group = user;
          mode = "0644";
        };
        sops.secrets."ssh-private" = {
          path = "${config.toh.host.home}/.ssh/toh";
          owner = user;
          group = user;
          mode = "0600";
        };
        sops.secrets."ssh-server-public" = {
          path = "/etc/ssh/ssh_host_toh.pub";
          owner = "root";
          group = "root";
          mode = "0644";
        };
        sops.secrets."ssh-server-private" = {
          path = "/etc/ssh/ssh_host_toh";
          owner = "root";
          group = "root";
          mode = "0600";
        };

        toh.cryl.host.openssh = {
          imports = builtins.concatMap (host: [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-public";
                to = "${host.name}-ssh-public";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-private";
                to = "${host.name}-ssh-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-public";
                to = "${host.name}-ssh-server-public";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-private";
                to = "${host.name}-ssh-server-private";
              };
            }
          ]) hosts;
          generations = [
            {
              generator = "copy";
              arguments = {
                from = "${hostname}-ssh-public";
                to = "ssh-public";
                renew = true;
              };
            }
            {
              generator = "copy";
              arguments = {
                from = "${hostname}-ssh-private";
                to = "ssh-private";
                renew = true;
              };
            }
            {
              generator = "copy";
              arguments = {
                from = "${hostname}-ssh-server-public";
                to = "ssh-server-public";
                renew = true;
              };
            }
            {
              generator = "copy";
              arguments = {
                from = "${hostname}-ssh-server-private";
                to = "ssh-server-private";
                renew = true;
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "ssh-authorized-keys";
                listing = {
                  type = "map";
                  value = builtins.listToAttrs (
                    builtins.map (host: {
                      name = "${lib.toUpper host.name}_SSH_PUBLIC";
                      value = "${host.name}-ssh-public";
                    }) hosts
                  );
                };
                template = builtins.concatStringsSep "\n" (
                  builtins.map (host: "{{${lib.toUpper host.name}_SSH_PUBLIC}}") hosts
                );
                renew = true;
              };
            }
            {
              generator = "mustache";
              arguments = {
                name = "ssh-known-hosts";
                listing = {
                  type = "map";
                  value = builtins.listToAttrs (
                    builtins.map (host: {
                      name = "${lib.toUpper host.name}_SSH_SERVER_PUBLIC";
                      value = "${host.name}-ssh-server-public";
                    }) hosts
                  );
                };
                template = builtins.concatStringsSep "\n" (
                  lib.flatten (
                    builtins.map (host: [
                      "${host.ip} {{${lib.toUpper host.name}_SSH_SERVER_PUBLIC}}"
                    ]) hosts
                  )
                );
                renew = true;
              };
            }
          ];
        };

        toh.cryl.cluster.openssh = {
          imports = builtins.concatMap (host: [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-public";
                to = "${host.name}-ssh-public";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-private";
                to = "${host.name}-ssh-private";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-public";
                to = "${host.name}-ssh-server-public";
                allow_fail = true;
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-private";
                to = "${host.name}-ssh-server-private";
                allow_fail = true;
              };
            }
          ]) hosts;
          generations = builtins.concatMap (host: [
            {
              generator = "ssh-key";
              arguments = {
                name = host.name;
                public = "${host.name}-ssh-public";
                private = "${host.name}-ssh-private";
              };
            }
            {
              generator = "ssh-key";
              arguments = {
                name = host.name;
                public = "${host.name}-ssh-server-public";
                private = "${host.name}-ssh-server-private";
              };
            }
          ]) hosts;
          exports = builtins.concatMap (host: [
            {
              exporter = "copy";
              arguments = {
                from = "${host.name}-ssh-public";
                to = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-public";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "${host.name}-ssh-private";
                to = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-private";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "${host.name}-ssh-server-public";
                to = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-public";
              };
            }
            {
              exporter = "copy";
              arguments = {
                from = "${host.name}-ssh-server-private";
                to = "${self.lib.cryl.directories.cluster}/${host.name}-ssh-server-private";
              };
            }
          ]) hosts;
        };
      };
    };
}
