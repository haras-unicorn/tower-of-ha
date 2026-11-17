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
        assertions = [
          {
            assertion = config.toh.meta.domains.machineSecret != null;
            message = ''
              ToH ddns-updater requires a domain name for the configured machine.
              Please set the required domain name secret for this machine
              with `toh.meta.domains.machineSecret`.
            '';
          }
        ];

        services.ddns-updater.enable = true;
        services.ddns-updater.environment = {
          CONFIG_FILEPATH = config.toh.meta.sops.secrets."ddns-updater-settings".path;
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

        toh.meta.services.ddns-updater = {
          endpoint.http.port = httpPort;
        };

        toh.meta.sops.secrets."ddns-updater-settings" = {
          owner = "ddns-updater";
          group = "ddns-updater";
          mode = "0400";
        };

        toh.meta.cryl.machine = lib.mkMerge [
          [
            {
              ddns-updater-settings = {
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
            }
          ]
          (lib.mkIf cfg.duckdns.enable (
            lib.mkBefore [
              {
                ddns-updater-duckdns = {
                  generations = [
                    {
                      generator = "mustache";
                      arguments = {
                        name = "ddns-updater-duckdns";
                        renew = true;
                        listing = {
                          type = "map";
                          value = {
                            DDNS_UPDATER_DUCKDNS_DOMAIN = "external/${config.toh.meta.domains.machineSecret}";
                            DDNS_UPDATER_DUCKDNS_TOKEN = "external/${cfg.duckdns.tokenSecret}";
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
              }
            ]
          ))
          (lib.mkIf cfg.cloudflare.enable (
            lib.mkBefore [
              {
                ddns-updater-cloudflare = {
                  generations = [
                    {
                      generator = "mustache";
                      arguments = {
                        name = "ddns-updater-cloudflare";
                        renew = true;
                        listing = {
                          type = "map";
                          value = {
                            DDNS_UPDATER_CLOUDFLARE_DOMAIN = "external/${config.toh.meta.domains.machineSecret}";
                            DDNS_UPDATER_CLOUDFLARE_TOKEN = "external/${cfg.cloudflare.tokenSecret}";
                            DDNS_UPDATER_CLOUDFLARE_ZONE_IDENTIFIER = "external/${cfg.cloudflare.zoneIdentifierSecret}";
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
              }
            ]
          ))
        ];
      };
    };
}
