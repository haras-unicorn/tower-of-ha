{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-ldap =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.ldap;

      app = selfLib.test.contract.app;

      clientMeta = machines.client.toh.meta;
      host = clientMeta.ldap.host;
      user = clientMeta.ldap.users.${app};

      search = "contract-ldap '(${clientMeta.ldap.usernameAttribute}=${app})' dn | grep -qx 'dn: ${user.dn}'";

      # NOTE: over LDAP, LLDAP changes only passwords and, for an admin, adds
      # users, so those are the changes an app could try
      changes = {
        password = ''
          dn: ${machines.server1.toh.meta.ldap.adminDistinguishedName}
          changetype: modify
          replace: userPassword
          userPassword: changed
        '';
        add = ''
          dn: uid=intruder,ou=people,${clientMeta.ldap.baseDistinguishedName}
          changetype: add
          objectClass: person
          objectClass: inetOrgPerson
          uid: intruder
          cn: intruder
          sn: intruder
        '';
      };

      # NOTE: refused for want of rights; the exit code alone would also say
      # no to a server that is down, so the output is checked
      refused = change: ''
        output = client.succeed("contract-ldap-modify /etc/contract-ldap/${change}.ldif 2>&1 || true")
        assert "Insufficient access" in output, output
      '';

      # NOTE: the app may only read, so what has to survive is its own entry
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "ldap";
        write = "None";
        holds = ''lambda _: """${search}"""'';
      };
    in
    {
      options.toh.test.contracts.ldap = selfLib.test.contract.options "ldap" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                ldap = config.toh.meta.ldap;

                bound = pkgs.writeShellApplication {
                  name = "contract-ldap-bound";
                  runtimeInputs = [ pkgs.openldap ];
                  text = ''
                    tool="$1"
                    shift
                    LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt \
                      "$tool" \
                      -H ${ldap.url} \
                      -D ${user.dn} \
                      -y <(printf %s "$(cat ${user.password})") \
                      "$@"
                  '';
                };

                asApp =
                  name: arguments:
                  pkgs.writeShellApplication {
                    inherit name;
                    runtimeInputs = [ pkgs.util-linux ];
                    text = ''
                      exec setpriv --reuid=${app} --regid=${app} --init-groups \
                        ${lib.getExe bound} ${arguments} "$@"
                    '';
                  };
              in
              {
                toh.meta.ldap.apps.${app}.permissions = [ selfLib.ldap.permissions.readOnly ];

                toh.pki.installCa = true;

                environment.systemPackages = [
                  (asApp "contract-ldap" "ldapsearch -LLL -o ldif_wrap=no -b ${ldap.baseDistinguishedName}")
                  (asApp "contract-ldap-modify" "ldapmodify -f")
                ];

                environment.etc = lib.mapAttrs' (
                  name: text: lib.nameValuePair "contract-ldap/${name}.ldif" { inherit text; }
                ) changes;
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("""${search}""", timeout=300)
              ${refused "password"}
              ${refused "add"}
              client.fail("contract-ldap '(uid=intruder)' dn | grep -q dn:")

              ${failover}
            '';
          }
        ]
      );
    };
}
