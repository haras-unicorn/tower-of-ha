{
  toh.lib.nixosModules.services-ddns-updater =
    {
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.ddns-updater;

      httpPort = 8000;
      healthPort = 9999;
    in
    {
      options.toh.services = {
        ddns-updater = {
          enable = lib.mkEnableOption "ddns-updater";

          duckdns = {
            enable = lib.mkEnableOption "ddns-updater DuckDNS";

            tokenSecret = lib.mkOption {
              type = lib.types.str;
              default = "ddns-updater-duckdns-token";
              description = "DuckDNS token secret";
            };
          };

          cloudflare = {
            enable = lib.mkEnableOption "ddns-updater Cloudflare";

            zoneIdentifierSecret = lib.mkOption {
              type = lib.types.str;
              default = "ddns-updater-cloudflare-zone-identifier";
              description = "Cloudflare zone identifier secret";
            };

            tokenSecret = lib.mkOption {
              type = lib.types.str;
              default = "ddns-updater-cloudflare-token";
              description = "Cloudflare token secret";
            };
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.ddns-updater.enable = true;
        services.ddns-updater.environment = {
          CONFIG_FILEPATH = config.sops.secrets."ddns-updater-settings".path;
          LISTENING_ADDRESS = ":${builtins.toString httpPort}";
          HEALTH_SERVER_ADDRESS = ":${builtins.toString healthPort}";
          # NOTE: keeping this here for easier debug later
          # GODEBUG = "netdns=go+2";
          # NOTE: bit of a hack to actually use the configured google server
          # or the test DNS server
          RESOLVER_ADDRESS = "${builtins.head config.networking.nameservers}:53";
          PERIOD = "5m";
        };

        users.groups.ddns-updater = { };

        users.users.ddns-updater = {
          group = "ddns-updater";
          isSystemUser = true;
        };

        systemd.services.ddns-updater = {
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = lib.mkForce "ddns-updater";
            Group = lib.mkForce "ddns-updater";
            Restart = lib.mkForce "always";
          };
        };

        networking.firewall.allowedTCPPorts = [
          httpPort
          healthPort
        ];

        toh.meta.services = [
          {
            name = "ddns-updater";
            port = httpPort;
            health = "http://";
          }
        ];

        sops.secrets."ddns-updater-settings" = {
          owner = "ddns-updater";
          group = "ddns-updater";
          mode = "0400";
        };

        # NOTE: this only runs after the provider generations because alphabetical order
        toh.cryl.machine.ddns-updater-settings = {
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "ddns-updater-settings";
                renew = true;
                listing = {
                  type = "map";
                  value =
                    lib.optionalAttrs cfg.duckdns.enable {
                      DDNS_UPDATER_DUCKDNS = "ddns-updater-duckdns";
                    }
                    // lib.optionalAttrs cfg.cloudflare.enable {
                      DDNS_UPDATER_CLOUDFLARE = "ddns-updater-cloudflare";
                    };
                };
                template = ''
                  {
                    "settings": [
                      ${builtins.concatStringsSep ", " (
                        lib.optional cfg.duckdns.enable "{{{DDNS_UPDATER_DUCKDNS}}}"
                        ++ lib.optional cfg.cloudflare.enable "{{{DDNS_UPDATER_CLOUDFLARE}}}"
                      )}
                    ]
                  }
                '';
              };
            }
          ];
        };

        toh.cryl.machine.ddns-updater-duckdns = lib.mkIf cfg.duckdns.enable {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.external}/${config.toh.meta.domains.machineSecret}";
                to = "ddns-updater-duckdns-domain";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.external}/${cfg.duckdns.tokenSecret}";
                to = "ddns-updater-duckdns-token";
              };
            }
          ];
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "ddns-updater-duckdns";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DDNS_UPDATER_DUCKDNS_DOMAIN = "ddns-updater-duckdns-domain";
                    DDNS_UPDATER_DUCKDNS_TOKEN = "ddns-updater-duckdns-token";
                  };
                };
                template = ''
                  {
                    "provider": "duckdns",
                    "domain": "{{{DDNS_UPDATER_DUCKDNS_DOMAIN}}}",
                    "token": "{{{DDNS_UPDATER_DUCKDNS_TOKEN}}}",
                    "ip_version": "ipv4"
                  }
                '';
              };
            }
          ];
        };

        toh.cryl.machine.ddns-updater-cloudflare = lib.mkIf cfg.cloudflare.enable {
          imports = [
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.external}/${config.toh.meta.domains.machineSecret}";
                to = "ddns-updater-cloudflare-domain";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.external}/${cfg.cloudflare.zoneIdentifierSecret}";
                to = "ddns-updater-cloudflare-zone-identifier";
              };
            }
            {
              importer = "copy";
              arguments = {
                from = "${tohLib.secrets.directories.external}/${cfg.cloudflare.tokenSecret}";
                to = "ddns-updater-cloudflare-token";
              };
            }
          ];
          generations = [
            {
              generator = "mustache";
              arguments = {
                name = "ddns-updater-cloudflare";
                renew = true;
                listing = {
                  type = "map";
                  value = {
                    DDNS_UPDATER_CLOUDFLARE_DOMAIN = "ddns-updater-cloudflare-domain";
                    DDNS_UPDATER_CLOUDFLARE_TOKEN = "ddns-updater-cloudflare-token";
                    DDNS_UPDATER_CLOUDFLARE_ZONE_IDENTIFIER = "ddns-updater-cloudflare-zone-identifier";
                  };
                };
                template = ''
                  {
                    "provider": "cloudflare",
                    "zone_identifier": "{{{DDNS_UPDATER_CLOUDFLARE_ZONE_IDENTIFIER}}}",
                    "domain": "{{{DDNS_UPDATER_CLOUDFLARE_DOMAIN}}}",
                    "ttl": 1,
                    "token": "{{{DDNS_UPDATER_CLOUDFLARE_TOKEN}}}",
                    "ip_version": "ipv4",
                    "ipv6_suffix": ""
                  }
                '';
              };
            }
          ];
        };
      };
    };
}
