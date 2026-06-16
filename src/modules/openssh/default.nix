# TODO: only allow from network

{
  toh.lib.nixosModules.services-openssh =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.openssh;

      user = config.toh.meta.user.user;

      machineName = config.toh.meta.machine.name;

      machines = tohLib.serviceMachines "openssh";
    in
    {
      options.toh.services = {
        openssh = {
          enable = lib.mkEnableOption "OpenSSH";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.overlays.cli-openssh = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [ pkgs.openssh ];
          extraTextFile = ./cli.nu;
        };

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
          "d ${config.toh.meta.user.home}/.ssh 0700 ${user} ${user} - -"
        ];
        # NOTE: a bit hacky but the "official" options are too static
        toh.meta.sops.secrets."ssh-authorized-keys" = {
          path = "${config.toh.meta.user.home}/.ssh/toh_authorized_keys";
          owner = user;
          group = user;
          mode = "0644";
        };
        # NOTE: a bit hacky but the "official" options are too static
        toh.meta.sops.secrets."ssh-known-hosts" = {
          path = "${config.toh.meta.user.home}/.ssh/toh_known_hosts";
          owner = user;
          group = user;
          mode = "0644";
        };
        toh.meta.sops.secrets."ssh-public" = {
          path = "${config.toh.meta.user.home}/.ssh/toh.pub";
          owner = user;
          group = user;
          mode = "0644";
        };
        toh.meta.sops.secrets."ssh-private" = {
          path = "${config.toh.meta.user.home}/.ssh/toh";
          owner = user;
          group = user;
          mode = "0600";
        };
        toh.meta.sops.secrets."ssh-server-public" = {
          path = "/etc/ssh/ssh_host_toh.pub";
          owner = "root";
          group = "root";
          mode = "0644";
        };
        toh.meta.sops.secrets."ssh-server-private" = {
          path = "/etc/ssh/ssh_host_toh";
          owner = "root";
          group = "root";
          mode = "0600";
        };

        toh.meta.cryl.machine = [
          {
            openssh = {
              generations = [
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/${machineName}-ssh-public";
                    to = "ssh-public";
                    renew = true;
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/${machineName}-ssh-private";
                    to = "ssh-private";
                    renew = true;
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/${machineName}-ssh-server-public";
                    to = "ssh-server-public";
                    renew = true;
                  };
                }
                {
                  generator = "copy";
                  arguments = {
                    from = "cluster/${machineName}-ssh-server-private";
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
                        builtins.map (machine: {
                          name = "${lib.toUpper machine.name}_SSH_PUBLIC";
                          value = "cluster/${machine.name}-ssh-public";
                        }) machines
                      );
                    };
                    template = builtins.concatStringsSep "\n" (
                      builtins.map (machine: "{{${lib.toUpper machine.name}_SSH_PUBLIC}}") machines
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
                        builtins.map (machine: {
                          name = "${lib.toUpper machine.name}_SSH_SERVER_PUBLIC";
                          value = "cluster/${machine.name}-ssh-server-public";
                        }) machines
                      );
                    };
                    template = builtins.concatStringsSep "\n" (
                      lib.flatten (
                        builtins.map (machine: [
                          "${machine.meta.network.ip} {{${lib.toUpper machine.name}_SSH_SERVER_PUBLIC}}"
                        ]) machines
                      )
                    );
                    renew = true;
                  };
                }
              ];
            };
          }
        ];

        toh.meta.cryl.cluster = [
          {
            openssh = {
              generations = builtins.concatMap (machine: [
                {
                  generator = "ssh-key";
                  arguments = {
                    name = machine.name;
                    public = "${machine.name}-ssh-public";
                    private = "${machine.name}-ssh-private";
                  };
                }
                {
                  generator = "ssh-key";
                  arguments = {
                    name = machine.name;
                    public = "${machine.name}-ssh-server-public";
                    private = "${machine.name}-ssh-server-private";
                  };
                }
              ]) machines;
            };
          }
        ];
      };
    };
}
