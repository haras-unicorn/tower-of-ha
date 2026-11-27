{ selfLib, lib, ... }:

let
  matrixSubmodule = {
    options = {
      enable = lib.mkEnableOption ''
        Matrix test server, a plain Synapse outside the cluster that the chat
        of the cluster can federate with
      '';

      domain = lib.mkOption {
        type = lib.types.str;
        default = "matrix.test";
        description = "Server name of the test server, and its domain.";
      };

      allowedIpRanges = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Private address ranges the test server may federate with, like the
          addresses of the proxies of the cluster.
        '';
      };
    };
  };
in
{
  self.lib.test.testModules.matrix =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.matrix;
    in
    {
      options.toh.test = {
        matrix = lib.mkOption {
          description = "Matrix test server";
          default = { };
          type = lib.types.submodule matrixSubmodule;
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            toh.test.dns.enable = true;
            toh.test.dns.zones = selfLib.dns.routeToIp [ cfg.domain ] machines.matrix.toh.meta.network.ip;

            toh.test.commands.prefix = lib.mkBefore ''
              matrix.wait_for_unit("matrix-synapse.service", timeout=120)
            '';
          }
          (selfLib.test.ofKind config.toh.test.kind {
            matrix.toh.test.matrix = cfg;
          })
        ]
      );
    };

  self.lib.test.nixosModules.matrix =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.test.matrix;

      synapseCfg = config.services.matrix-synapse;

      secrets = config.toh.meta.sops.secrets;

      owner = "matrix-synapse";

      federationPort = 8448;
      localPort = 8008;

      # NOTE: tests retry what fails while the cluster comes up, and the
      # default rate limits of Synapse would answer the retries for good
      unlimited = {
        per_second = 1000;
        burst_count = 1000;
      };

      registerUser = pkgs.writeShellApplication {
        name = "matrix-register-user";
        runtimeInputs = [ synapseCfg.package ];
        text = ''
          register_new_matrix_user \
            --config ${synapseCfg.configFile} \
            --user "$1" \
            --password "$2" \
            --no-admin \
            http://127.0.0.1:${builtins.toString localPort}
        '';
      };
    in
    {
      options.toh.test = {
        matrix = lib.mkOption {
          type = lib.types.submodule matrixSubmodule;
          default = { };
          description = "Matrix test server";
        };
      };

      config = lib.mkIf cfg.enable {
        services.matrix-synapse = {
          enable = true;
          settings = {
            server_name = cfg.domain;
            public_baseurl = "https://${cfg.domain}:${builtins.toString federationPort}";
            database.name = "sqlite3";
            enable_registration = false;
            registration_shared_secret_path = secrets."matrix-registration".path;
            report_stats = false;
            trusted_key_servers = [ ];
            ip_range_whitelist = cfg.allowedIpRanges;
            tls_certificate_path = secrets."matrix-public".path;
            tls_private_key_path = secrets."matrix-private".path;
            rc_message = unlimited;
            rc_joins.local = unlimited;
            rc_invites = {
              per_room = unlimited;
              per_user = unlimited;
              per_issuer = unlimited;
            };
            rc_login = {
              address = unlimited;
              account = unlimited;
              failed_attempts = unlimited;
            };
            # NOTE: 8448 is where other servers look for a server that serves
            # no well-known file, and the local listener is for registering
            # users without TLS
            listeners = [
              {
                port = federationPort;
                bind_addresses = [ "0.0.0.0" ];
                type = "http";
                tls = true;
                x_forwarded = false;
                resources = [
                  {
                    names = [
                      "client"
                      "federation"
                    ];
                    compress = false;
                  }
                ];
              }
              {
                port = localPort;
                bind_addresses = [ "127.0.0.1" ];
                type = "http";
                tls = false;
                x_forwarded = false;
                resources = [
                  {
                    names = [ "client" ];
                    compress = false;
                  }
                ];
              }
            ];
          };
        };

        systemd.services.matrix-synapse = {
          after = [ "sops-install-secrets.service" ];
          requires = [ "sops-install-secrets.service" ];
        };

        environment.systemPackages = [ registerUser ];

        networking.firewall.allowedTCPPorts = [ federationPort ];
        # NOTE: other servers first ask for a well-known file on 443, and a
        # dropped connection makes them wait until it times out and then back
        # off from this server, where a refused one sends them on to 8448
        networking.firewall.rejectPackets = true;

        toh.pki.installCa = true;

        toh.meta.sops.secrets = {
          "matrix-public" = {
            inherit owner;
            group = owner;
            mode = "0400";
          };
          "matrix-private" = {
            inherit owner;
            group = owner;
            mode = "0400";
          };
          "matrix-registration" = {
            inherit owner;
            group = owner;
            mode = "0400";
          };
        };

        toh.meta.cryl.machine = [
          {
            matrix = {
              generations = [
                {
                  generator = "tls-leaf";
                  arguments = {
                    common_name = cfg.domain;
                    organization = "ToH";
                    sans = [
                      cfg.domain
                      "localhost"
                      "127.0.0.1"
                      config.toh.meta.network.ip
                    ];
                    config = "matrix-cert-config";
                    request_config = "matrix-cert-request-config";
                    private = "matrix-private";
                    request = "matrix-cert-request";
                    ca_private = "cluster/openssl-ca-private";
                    ca_public = "cluster/openssl-ca-public";
                    serial = "cluster/openssl-ca-serial";
                    public = "matrix-public";
                    renew = true;
                  };
                }
                {
                  generator = "key";
                  arguments = {
                    name = "matrix-registration";
                  };
                }
              ];
            };
          }
        ];
      };
    };
}
