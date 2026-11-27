{ selfLib, ... }:

{
  self.nixosModules.services-maddy.flake = true;
  self.nixosModules.services-maddy.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.maddy;

      anyMachines = selfLib.cluster.anyServiceMachines config "maddy";

      # NOTE: not in /run/maddy, the runtime directory of maddy, which goes
      # away whenever maddy stops, so the file was gone at the next start;
      # this one is the runtime directory of maddy-env and stays while that
      # stays active
      envDirectory = "maddy-secrets";
      env = "/run/${envDirectory}/secrets.env";

      # NOTE: because proxy is on 25 statically
      smtpPort = 30025;
      submissionPort = 587;
      imapPort = 143;

      owner = "maddy";
      group = "maddy";

      dbConfig = config.toh.meta.database;
      dbInst = config.toh.meta.database.instances.maddy;

      s3Bucket = config.toh.meta.s3.buckets.maddy;

      ldapConfig = config.toh.meta.ldap;
      ldapUser = config.toh.meta.ldap.users.maddy;

      clusterEmailApps = builtins.zipAttrsWith (_: builtins.head) (
        builtins.map (machine: machine.meta.email.apps) config.toh.meta.cluster.machineList
      );

      accounts = [ "maddy" ] ++ builtins.attrNames clusterEmailApps;

      imapProxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.maddy-imap.endpoint;
      smtpProxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.maddy-smtp.endpoint;
      submissionProxyAttrs = selfLib.services.endpoint.toAttrs config.toh.meta.proxies.maddy-submission.endpoint;
    in
    {
      options.toh.services = {
        maddy = {
          enable = lib.mkEnableOption "Maddy mail server";

          accountsRetrySeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = ''
              Seconds between tries to create the IMAP accounts, which fail
              until the database user of Maddy is ready.
            '';
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf anyMachines {
          toh.meta.email = {
            admin = selfLib.email.makeAddress {
              name = "maddy";
              host = config.toh.meta.email.domain;
            };

            submission = {
              inherit (submissionProxyAttrs) host port;
            };

            imap = {
              inherit (imapProxyAttrs) host port;
            };
          };
        })
        (lib.mkIf cfg.enable {
          services.maddy = {
            user = owner;
            group = group;
            enable = true;
            hostname = config.toh.meta.email.domain;
            primaryDomain = config.toh.meta.email.domain;
            localDomains = [
              smtpProxyAttrs.host
              submissionProxyAttrs.host
              imapProxyAttrs.host
            ];
            openFirewall = false;
            secrets = [
              "${env}"
            ];
            tls.loader = "off";
            config =
              let
                ldapBaseUsersDn =
                  lib.optionalString (ldapConfig.additionalUsersDn != null) ldapConfig.additionalUsersDn
                  + ","
                  + ldapConfig.baseDistinguishedName;

                ldapTemplateAttr = lib.optionalString (
                  ldapConfig.usernameAttribute != null
                ) "dn_template ${ldapConfig.usernameAttribute}={username},${ldapBaseUsersDn}";

                imapSqlDriver =
                  if dbConfig.protocol == "postgresql" then
                    "postgres"
                  else if dbConfig.protocol == "sqlite3" then
                    "sqlite3"
                  else
                    builtins.throw "Unsupported IMAP SQL database";

                imapSqlDsn =
                  "user=maddy"
                  + " password={env:MADDY_DB_PASSWORD}"
                  + " host=${config.toh.meta.database.host}"
                  + " port=${builtins.toString config.toh.meta.database.port}"
                  + " dbname=maddy"
                  + " "
                  + builtins.concatStringsSep " " (
                    lib.mapAttrsToList (name: value: "${name}=${builtins.toString value}") dbInst.parameters
                  );

                s3Host = "${config.toh.meta.s3.host}:${builtins.toString config.toh.meta.s3.port}";

                submissionBind = "tcp://${config.toh.meta.network.ip}:${builtins.toString submissionPort}";

                imapBind = "tcp://${config.toh.meta.network.ip}:${builtins.toString imapPort}";

                smtpBind = "tcp://${config.toh.meta.network.ip}:${builtins.toString smtpPort}";
              in
              ''
                auth_map email_localpart

                auth.ldap local_authdb {
                  urls ${config.toh.meta.ldap.url}
                  bind plain "${ldapUser.dn}" {env:MADDY_LDAP_BIND_PASSWORD}
                  ${ldapTemplateAttr}
                }

                storage.imapsql local_mailboxes {
                  driver ${imapSqlDriver}
                  dsn "${imapSqlDsn}"
                  delivery_map email_localpart
                  msg_store s3 {
                    endpoint ${s3Host}
                    secure yes
                    access_key {env:MADDY_S3_ACCESS_KEY}
                    secret_key {env:MADDY_S3_SECRET_KEY}
                    bucket maddy
                    region ${config.toh.meta.s3.region}
                  }
                }

                smtp ${smtpBind} {
                  hostname ${smtpProxyAttrs.host}
                  limits {
                    all rate 20 1s
                    all concurrency 10
                  }
                  sasl_login yes
                  auth &local_authdb
                  dmarc yes
                  check {
                    require_mx_record
                    dkim
                    spf
                  }
                  source $(local_domains) {
                    reject 501 5.1.8 "Use Submission for outgoing SMTP"
                  }
                  default_source {
                    destination $(local_domains) {
                      deliver_to &local_routing
                    }
                    default_destination {
                      reject 550 5.1.1 "User doesn't exist"
                    }
                  }
                }

                submission ${submissionBind} {
                  hostname ${config.toh.meta.email.domain}
                  limits {
                    all rate 50 1s
                  }
                  sasl_login yes
                  auth &local_authdb
                  source $(local_domains) {
                    check {
                      authorize_sender {
                        prepare_email &local_rewrites
                        user_to_email identity
                      }
                    }
                    destination $(local_domains) {
                      deliver_to &local_routing
                    }
                    default_destination {
                      modify {
                        dkim $(primary_domain) $(local_domains) default
                      }
                      deliver_to &remote_queue
                    }
                  }
                  default_source {
                    reject 501 5.1.8 "Non-local sender domain"
                  }
                }

                imap ${imapBind} {
                  auth &local_authdb
                  sasl_login yes
                  storage &local_mailboxes
                  storage_map email_localpart
                }

                table.chain local_rewrites {
                  optional_step regexp "(.+)\+(.+)@(.+)" "$1@$3"
                  optional_step static {
                    entry postmaster postmaster@$(primary_domain)
                  }
                }

                msgpipeline local_routing {
                  destination $(local_domains) {
                    modify {
                      replace_rcpt &local_rewrites
                    }
                    deliver_to &local_mailboxes
                  }
                  default_destination {
                    reject 550 5.1.1 "User doesn't exist"
                  }
                }

                target.remote outbound_delivery {
                  limits {
                    destination rate 20 1s
                    destination concurrency 10
                  }
                  mx_auth {
                    dane
                    mtasts {
                      cache fs
                      fs_dir mtasts_cache/
                    }
                    local_policy {
                      min_tls_level encrypted
                      min_mx_level none
                    }
                  }
                }

                target.queue remote_queue {
                  target &outbound_delivery
                  autogenerated_msg_domain $(primary_domain)
                  bounce {
                    destination postmaster $(local_domains) {
                      deliver_to &local_routing
                    }
                    default_destination {
                      reject 550 5.0.0 "Refusing to send DSNs to non-local addresses"
                    }
                  }
                }
              '';
          };

          systemd.services.maddy-env = {
            description = "Maddy environment file generation";
            wantedBy = [ "maddy.service" ];
            before = [ "maddy.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = envDirectory;
              RuntimeDirectoryMode = "0711";
            };
            script = ''
              echo "MADDY_LDAP_BIND_PASSWORD=$(cat ${ldapUser.password})" > ${env}
              echo "MADDY_DB_PASSWORD=$(cat ${dbInst.password})" >> ${env}
              echo "MADDY_S3_ACCESS_KEY=$(cat ${s3Bucket.keyId})" >> ${env}
              echo "MADDY_S3_SECRET_KEY=$(cat ${s3Bucket.secretKey})" >> ${env}
              chown ${owner}:${group} ${env}
              chmod 400 ${env}
            '';
          };

          systemd.services.maddy = {
            wantedBy = [
              "toh-database-online.target"
              "toh-ldap-online.target"
              "toh-s3-online.target"
            ];
            requires = [
              "toh-database-online.target"
              "toh-ldap-online.target"
              "toh-s3-online.target"
            ];
            after = [
              "toh-database-online.target"
              "toh-ldap-online.target"
              "toh-s3-online.target"
            ];
          };

          systemd.targets.toh-email-online = {
            wantedBy = [ "maddy.service" ];
            bindsTo = [ "maddy.service" ];
            after = [ "maddy.service" ];
          };

          networking.firewall.allowedTCPPorts = [
            smtpPort
            submissionPort
            imapPort
          ];

          toh.meta.services.maddy-imap = {
            endpoint.tcp = {
              port = imapPort;
              layer7Protocol = "imap";
            };
            health.endpoint.tcp = {
              port = imapPort;
            };
          };

          toh.meta.services.maddy-smtp = {
            endpoint.tcp = {
              port = smtpPort;
              layer7Protocol = "smtp";
            };
            health.endpoint.tcp = {
              port = smtpPort;
            };
          };

          toh.meta.services.maddy-submission = {
            endpoint.submit = {
              port = submissionPort;
            };
            health.endpoint.tcp = {
              port = submissionPort;
            };
          };

          programs.rust-motd.settings.service_status.Maddy = "maddy";

          toh.meta.ldap.apps.maddy = {
            user = owner;
            group = group;
            permissions = [ selfLib.ldap.permissions.readOnly ];
          };

          toh.meta.database.apps.maddy = {
            user = owner;
            group = group;
          };

          # NOTE: services.maddy.ensureAccounts exits 0 when the database
          # refuses it, so it gives up for good when it starts before the
          # database user of maddy is ready
          systemd.services.maddy-accounts = {
            description = "Maddy IMAP accounts";
            wantedBy = [ "maddy.service" ];
            after = [ "maddy.service" ];
            bindsTo = [ "maddy.service" ];
            unitConfig.StartLimitIntervalSec = 0;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = owner;
              Group = group;
              EnvironmentFile = env;
              Restart = "on-failure";
              RestartSec = cfg.accountsRetrySeconds;
            };
            script = lib.getExe (
              pkgs.tohPackages.writeNushellApplication {
                name = "maddy-accounts";
                runtimeInputs = [ config.services.maddy.package ];
                text = ''
                  let accounts = r#'${builtins.toJSON accounts}'# | from json
                  let existing = maddyctl imap-acct list | lines
                  for account in ($accounts | where $it not-in $existing) {
                    maddyctl imap-acct create $account
                  }
                '';
              }
            );
          };

          toh.meta.s3.apps.maddy = {
            user = owner;
            group = group;
          };
        })
      ];
    };
}
