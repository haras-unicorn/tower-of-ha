{
  toh.lib.nixosModules.services-traefik =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.traefik;

      httpsPort = 443;
      # NOTE: not on "localhost" because resolved has "127.0.0.53:53"
      consulEndpoint = "${config.toh.meta.network.ip}:8500";
    in
    {
      options.toh.services = {
        traefik = {
          enable = lib.mkEnableOption "Traefik";
        };
      };

      config = lib.mkIf cfg.enable {
        services.traefik.enable = true;
        services.traefik.group = "traefik";

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
                  "Host(`traefik.${config.toh.meta.domains.service}`)"
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
              defaultRule = "Host(`{{ normalize .Name }}.${config.toh.meta.domains.service}`)";
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

        systemd.services.traefik.serviceConfig = {
          Restart = lib.mkForce "always";
        };

        networking.firewall.allowedTCPPorts = [
          httpsPort
        ];

        programs.rust-motd.settings = {
          service_status = {
            Traefik = "traefik";
          };
        };

        toh.meta.services = [
          {
            name = "traefik";
            port = httpsPort;
            health = "tcp://";
          }
        ];

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

        toh.cryl.machine.traefik = {
          generations = [
            {
              generator = "tls-leaf";
              arguments = {
                common_name = "toh";
                organization = "ToH";
                sans = [
                  "*.${config.toh.meta.domains.service}"
                  "localhost"
                  "${config.toh.meta.network.ip}"
                  "127.0.0.1"
                ];
                config = "traefik-cert-config";
                request_config = "traefik-cert-request-config";
                private = "traefik-private";
                request = "traefik-cert-request";
                ca_private = "cluster/openssl-ca-private";
                ca_public = "cluster/openssl-ca-public";
                serial = "cluster/openssl-ca-serial";
                public = "traefik-public";
                renew = true;
              };
            }
          ];
        };

        toh.ssl.generateCa = true;
      };
    };
}
