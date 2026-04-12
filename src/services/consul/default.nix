{ self, ... }:

{
  toh.domains.topLevel = "toh";
  toh.domains.service = "service.toh";
  toh.domains.node = "node.toh";

  flake.nixosModules.services-consul =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      etc = "/etc/consul";
      certs = "${etc}/certs";
      # NOTE: consul complains how it must end with .json or .hcl
      configPath = "${etc}/config.json";
      port = 8500;
      rpcPort = 8300;
      serfLanPort = 8301;
      serfWanPort = 8302;
      grpcTlsPort = 8503;
      dnsPort = 53;
      hosts = builtins.map (x: x.ip) (
        builtins.filter (
          x:
          if lib.hasAttrByPath [ "system" "toh" "consul" "enable" ] x then
            x.system.toh.consul.enable
          else
            false
        ) config.toh.host.hosts
      );
      retryJoinHosts = builtins.filter (x: x != config.toh.host.ip) hosts;
    in
    {
      options.toh = {
        consul = {
          enable = lib.mkEnableOption "Consul";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (!config.toh.consul.enable) {
          networking.networkmanager.dispatcherScripts = [
            {
              source = pkgs.writeText "disable-dnssec-${config.toh.host.interface}" ''
                if [ "$1" = "${config.toh.host.interface}" ] && [ "$2" = "up" ]; then
                  ${pkgs.systemd}/bin/resolvectl dnssec $1 off
                  ${pkgs.systemd}/bin/resolvectl dnsovertls $1 off
                  ${pkgs.systemd}/bin/resolvectl domain $1 ~${config.toh.domains.topLevel}
                  ${pkgs.systemd}/bin/resolvectl dns $1 ${builtins.concatStringsSep " " hosts}
                fi
              '';
              type = "basic";
            }
          ];

        })
        (lib.mkIf config.toh.consul.enable {
          networking.networkmanager.ensureProfiles.profiles.${config.toh.host.interface} = {
            connection = {
              id = config.toh.host.interface;
            };
            ipv4 = {
              dns = "127.0.0.1";
              dns-search = "~${config.toh.domains.topLevel};";
            };
          };

          systemd.services.consul.wantedBy = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.consul.after = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.consul.requires = [
            "toh-network-online.target"
            "toh-time-synchronized.target"
          ];
          systemd.services.consul.serviceConfig = {
            Restart = lib.mkForce "always";
          };

          services.consul.enable = true;
          services.consul.webUi = true;
          services.consul.dropPrivileges = false;

          services.consul.extraConfig = {
            domain = config.toh.domains.topLevel;
            datacenter = "toh";
            node_name = config.toh.host.name;
            server = true;
            bootstrap_expect = builtins.length hosts;
            retry_join = retryJoinHosts;
            # NOTE: not on "0.0.0.0" because resolved has "127.0.0.53:53"
            client_addr = config.toh.host.ip;
            # NOTE: like this instead of through nixpkgs
            # because then it tries to wait for the device
            # but vpn doesn't work that way
            bind_addr = config.toh.host.ip;
            advertise_addr = config.toh.host.ip;

            ui_config = {
              enabled = true;
            };

            connect = {
              enabled = true;
            };

            log_level = "INFO";
            enable_syslog = true;

            encrypt_verify_incoming = true;
            encrypt_verify_outgoing = true;

            acl.enabled = false;
            # acl = {
            #   enabled = true;
            #   default_policy = "deny";
            #   enable_token_persistence = true;
            # };

            tls = {
              defaults = {
                verify_incoming = true;
                verify_outgoing = true;
                ca_file = "${certs}/ca.crt";
                cert_file = "${certs}/consul.crt";
                key_file = "${certs}/consul.key";
              };
              https = {
                verify_incoming = false;
              };
            };

            ports = {
              http = -1;
              https = port;
              dns = dnsPort;
              grpc = -1;
              grpc_tls = grpcTlsPort;
              serf_lan = serfLanPort;
              serf_wan = serfWanPort;
              server = rpcPort;
            };

            services = builtins.map (service: {
              inherit (service) name port address;
              tags = [
                "toh.enable=true"
              ]
              ++ (lib.optional service.tls "toh.http.services.${service.name}.loadbalancer.server.scheme=https");
              check =
                let
                  protocol = builtins.head (
                    builtins.filter (protocol: lib.hasPrefix protocol service.health) self.lib.services.protocols
                  );
                  key = if protocol == "tcp://" then "tcp" else "http";
                in
                {
                  ${key} =
                    protocol
                    + service.address
                    + ":"
                    + builtins.toString service.port
                    + lib.removePrefix protocol service.health;
                  timeout = "30s";
                  interval = "10s";
                };
            }) config.toh.services;
          };

          toh.services = [
            {
              name = "consul-ui";
              port = port;
              tls = true;
              health = "https:///v1/status/leader";
            }
          ];

          services.consul.extraConfigFiles = [
            config.sops.secrets."consul-config".path
          ];

          networking.firewall.allowedTCPPorts = [
            port
            rpcPort
            serfLanPort
            serfWanPort
            grpcTlsPort
            dnsPort
          ];

          networking.firewall.allowedUDPPorts = [
            serfLanPort
            serfWanPort
            dnsPort
          ];

          programs.rust-motd.settings = {
            service_status = {
              Consul = "consul";
            };
          };

          sops.secrets."consul-config" = {
            path = configPath;
            owner = config.systemd.services.consul.serviceConfig.User;
            group = config.systemd.services.consul.serviceConfig.User;
            mode = "0400";
          };
          sops.secrets."consul-ca-public" = {
            key = "openssl-ca-public";
            path = "${certs}/ca.crt";
            owner = config.systemd.services.consul.serviceConfig.User;
            group = config.systemd.services.consul.serviceConfig.User;
            mode = "0644";
          };
          sops.secrets."consul-public" = {
            path = "${certs}/consul.crt";
            owner = config.systemd.services.consul.serviceConfig.User;
            group = config.systemd.services.consul.serviceConfig.User;
            mode = "0644";
          };
          sops.secrets."consul-private" = {
            path = "${certs}/consul.key";
            owner = config.systemd.services.consul.serviceConfig.User;
            group = config.systemd.services.consul.serviceConfig.User;
            mode = "0400";
          };

          toh.cryl.host.consul = {
            imports = [
              {
                importer = "copy";
                arguments = {
                  from = "${self.lib.cryl.directories.cluster}/consul-gossip-key";
                  to = "consul-gossip-key";
                };
              }
              {
                importer = "copy";
                arguments = {
                  from = "${self.lib.cryl.directories.cluster}/consul-bootstrap-token";
                  to = "consul-bootstrap-token";
                };
              }
            ];
            generations = [
              {
                generator = "tls-leaf";
                arguments = {
                  common_name = "toh";
                  organization = "ToH";
                  sans = [
                    "consul.${config.toh.domains.service}"
                    "consul-ui.${config.toh.domains.service}"
                    "localhost"
                    "${config.toh.host.ip}"
                    "127.0.0.1"
                  ];
                  config = "consul-cert-config";
                  request_config = "consul-cert-request-config";
                  private = "consul-private";
                  request = "consul-cert-request";
                  ca_private = "openssl-ca-private";
                  ca_public = "openssl-ca-public";
                  serial = "openssl-ca-serial";
                  public = "consul-public";
                  renew = true;
                };
              }
              {
                generator = "mustache";
                arguments = {
                  name = "consul-config";
                  renew = true;
                  listing = {
                    type = "map";
                    value = {
                      CONSUL_GOSSIP_KEY = "consul-gossip-key";
                      CONSUL_BOOTSTRAP_TOKEN = "consul-bootstrap-token";
                    };
                  };
                  template = ''
                    {
                      "encrypt": "{{CONSUL_GOSSIP_KEY}}",
                      "acl": {
                        "tokens": {
                          "initial_management": "{{CONSUL_BOOTSTRAP_TOKEN}}"
                        }
                      }
                    }
                  '';
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

          toh.cryl.cluster.consul = {
            imports = [
              {
                importer = "copy";
                arguments = {
                  from = "${self.lib.cryl.directories.cluster}/consul-gossip-key";
                  to = "consul-gossip-key";
                  allow_fail = true;
                };
              }
              {
                importer = "copy";
                arguments = {
                  from = "${self.lib.cryl.directories.cluster}/consul-bootstrap-token";
                  to = "consul-bootstrap-token";
                  allow_fail = true;
                };
              }
            ];
            generations = [
              {
                generator = "key";
                arguments = {
                  name = "consul-gossip-key";
                };
              }
              {
                generator = "key";
                arguments = {
                  name = "consul-bootstrap-token";
                };
              }
            ];
            exports = [
              {
                exporter = "copy";
                arguments = {
                  from = "consul-gossip-key";
                  to = "${self.lib.cryl.directories.cluster}/consul-gossip-key";
                };
              }
              {
                exporter = "copy";
                arguments = {
                  from = "consul-bootstrap-token";
                  to = "${self.lib.cryl.directories.cluster}/consul-bootstrap-token";
                };
              }
            ];
          };
        })
      ];
    };
}
