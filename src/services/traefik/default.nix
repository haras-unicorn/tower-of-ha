{ self, ... }:

{
  flake.nixosModules.services-traefik =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      httpsPort = 443;
      # NOTE: not on "localhost" because resolved has "127.0.0.53:53"
      consulEndpoint = "${config.toh.host.ip}:8500";
    in
    {
      options.toh = {
        traefik.enable = lib.mkEnableOption "Traefik";
      };

      config = lib.mkIf config.toh.traefik.enable {
        services.traefik.enable = true;
        services.traefik.group = "traefik";

        systemd.services.traefik.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        services.traefik.dynamicConfigOptions = {
          tls = {
            certificates = [
              {
                certFile = config.sops.secrets."traefik-public".path;
                keyFile = config.sops.secrets."traefik-private".path;
                stores = [ "default" ];
              }
            ];
            stores = {
              default = {
                defaultCertificate = {
                  certFile = config.sops.secrets."traefik-public".path;
                  keyFile = config.sops.secrets."traefik-private".path;
                };
              };
            };
          };

          http = {
            middlewares = {
              traefik-root-redirect.redirectregex = {
                regex = "^/$";
                replacement = "/dashboard/";
                permanent = true;
              };
              traefik-dashboard-slash.redirectregex = {
                regex = "^/dashboard$";
                replacement = "/dashboard/";
                permanent = true;
              };
            };

            routers = {
              dashboard = {
                rule =
                  "Host(`traefik.${config.toh.domains.service}`)"
                  + " && (PathPrefix(`/api`) || PathPrefix(`/dashboard`) || Path(`/`))";
                entryPoints = [ "websecure" ];
                service = "api@internal";
                middlewares = [
                  "traefik-root-redirect"
                  "traefik-dashboard-slash"
                ];
              };
            };
          };
        };

        services.traefik.staticConfigOptions = {
          api = {
            dashboard = true;
          };

          entryPoints = {
            websecure = {
              address = ":${builtins.toString httpsPort}";
              http.tls = { };
            };
          };

          providers = {
            consul = {
              rootKey = "toh";
              endpoints = [ consulEndpoint ];
              tls = {
                ca = config.sops.secrets."traefik-ca-public".path;
                cert = config.sops.secrets."traefik-public".path;
                key = config.sops.secrets."traefik-private".path;
                insecureSkipVerify = false;
              };
            };

            consulCatalog = {
              prefix = "toh";
              exposedByDefault = false;
              defaultRule = "Host(`{{ normalize .Name }}.${config.toh.domains.service}`)";
              endpoint = {
                address = consulEndpoint;
                scheme = "https";
                tls = {
                  ca = config.sops.secrets."traefik-ca-public".path;
                  cert = config.sops.secrets."traefik-public".path;
                  key = config.sops.secrets."traefik-private".path;
                  insecureSkipVerify = false;
                };
              };
            };
          };
        };

        toh.services = [
          {
            name = "traefik";
            port = httpsPort;
            health = "tcp://";
          }
        ];

        networking.firewall.allowedTCPPorts = [
          httpsPort
        ];

        programs.rust-motd.settings = {
          service_status = {
            Traefik = "traefik";
          };
        };

        sops.secrets."traefik-ca-public" = {
          key = "openssl-ca-public";
          owner = config.systemd.services.traefik.serviceConfig.User;
          group = config.systemd.services.traefik.serviceConfig.User;
          mode = "0644";
        };
        sops.secrets."traefik-public" = {
          owner = config.systemd.services.traefik.serviceConfig.User;
          group = config.systemd.services.traefik.serviceConfig.User;
          mode = "0644";
        };
        sops.secrets."traefik-private" = {
          owner = config.systemd.services.traefik.serviceConfig.User;
          group = config.systemd.services.traefik.serviceConfig.User;
          mode = "0400";
        };

        toh.cryl.host.traefik = {
          generations = [
            {
              generator = "tls-leaf";
              arguments = {
                common_name = "toh";
                organization = "ToH";
                sans = [
                  "*.${config.toh.domains.service}"
                  "localhost"
                  "${config.toh.host.ip}"
                  "127.0.0.1"
                ];
                config = "traefik-cert-config";
                request_config = "traefik-cert-request-config";
                private = "traefik-private";
                request = "traefik-cert-request";
                ca_private = "openssl-ca-private";
                ca_public = "openssl-ca-public";
                serial = "openssl-ca-serial";
                public = "traefik-public";
                renew = true;
              };
            }
          ];
        };

        toh.cryl.host.openssl-ca = {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/openssl-ca-public";
                to = "openssl-ca-public";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/openssl-ca-private";
                to = "openssl-ca-private";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${self.lib.cryl.directories.cluster}/openssl-ca-serial";
                to = "openssl-ca-serial";
              };
            }
          ];
        };
      };
    };
}
