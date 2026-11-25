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

                search = pkgs.writeShellApplication {
                  name = "contract-ldap-search";
                  runtimeInputs = [ pkgs.openldap ];
                  text = ''
                    LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt \
                      ldapsearch -LLL -o ldif_wrap=no \
                      -H ${ldap.url} \
                      -D ${user.dn} \
                      -y <(printf %s "$(cat ${user.password})") \
                      -b ${ldap.baseDistinguishedName} \
                      "$@"
                  '';
                };

                client = pkgs.writeShellApplication {
                  name = "contract-ldap";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      ${lib.getExe search} "$@"
                  '';
                };
              in
              {
                toh.meta.ldap.apps.${app}.permissions = [ selfLib.ldap.permissions.readOnly ];

                toh.pki.installCa = true;

                environment.systemPackages = [ client ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("""${search}""", timeout=300)

              ${failover}
            '';
          }
        ]
      );
    };
}
