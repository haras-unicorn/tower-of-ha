{ selfLib, ... }:

# NOTE: the contract is that the bao CLI works with the implementation, which
# only Vault and OpenBao offer; the CLI of ToH is built on it, so the secrets
# capability cannot do without it. The client uses the token its machine
# fetched (every machine of a cluster with a secrets service gets one) and the
# place the machine may write to, so the contract is tied to how OpenBao lays
# out its secrets.

{
  self.lib.test.testModules.contracts-secrets =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.secrets;

      value = "works";

      clientMeta = machines.client.toh.meta;
      proxy = clientMeta.proxies.secrets.endpoint;

      # NOTE: the machine may only write its own secret, so every value is a
      # field of it
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "secrets";
        write = ''lambda value: f"contract-secrets write-value {value}"'';
        holds = ''lambda value: f"contract-secrets read-value {value} | grep -x {value}"'';
      };
    in
    {
      options.toh.test.contracts.secrets = selfLib.test.contract.options "secrets" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${(selfLib.services.endpoint.toAttrs proxy).host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                secrets = config.toh.meta.secrets;
                secretPath = "${secrets.keys.machines}/${config.toh.meta.machine.name}";

                contract = pkgs.writeShellApplication {
                  name = "contract-secrets";
                  runtimeInputs = [ pkgs.openbao ];
                  text = ''
                    BAO_ADDR=${selfLib.services.endpoint.toUrl proxy { }}
                    export BAO_ADDR
                    BAO_TOKEN="$(cat ${secrets.files.token})"
                    export BAO_TOKEN

                    case "$1" in
                      write)
                        printf %s ${value} \
                          | bao kv put -mount=${secrets.keys.mount} ${secretPath} value=-
                        ;;
                      read)
                        bao kv get -mount=${secrets.keys.mount} -field=value ${secretPath}
                        ;;
                      write-value)
                        printf %s "$2" \
                          | bao kv patch -method=rw -mount=${secrets.keys.mount} ${secretPath} "$2=-"
                        ;;
                      read-value)
                        bao kv get -mount=${secrets.keys.mount} -field="$2" ${secretPath}
                        ;;
                    esac
                  '';
                };
              in
              {
                toh.pki.installCa = true;

                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-secrets write", timeout=300)
              client.wait_until_succeeds("contract-secrets read | grep -qx ${value}", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
