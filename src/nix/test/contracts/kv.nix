{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-kv =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.kv;

      app = selfLib.test.contract.app;
      prefix = "${app}:";
      key = "${prefix}value";
      value = "works";

      clientMeta = machines.client.toh.meta;
      host = clientMeta.kv.host;

      # NOTE: the store replicates after it answers, so a write only counts
      # once WAIT says a replica has it; a plain write can be lost with the
      # primary, see docs/behavior.md
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "kv";
        write = ''lambda value: f"printf 'SET ${prefix}{value} {value}\nWAIT 1 5000\n' | contract-kv | tr '\n' ' ' | grep -xE 'OK [1-9][0-9]* '"'';
        holds = ''lambda value: f"contract-kv GET ${prefix}{value} | grep -x {value}"'';
      };
    in
    {
      options.toh.test.contracts.kv = selfLib.test.contract.options "kv" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                kv = config.toh.meta.kv;
                instance = kv.instances.${app};

                clients.rediss = pkgs.writeShellApplication {
                  name = "contract-kv";
                  runtimeInputs = [
                    pkgs.valkey
                    pkgs.util-linux
                  ];
                  text = ''
                    VALKEYCLI_AUTH="$(cat ${instance.password})" \
                      exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      valkey-cli --tls \
                      --cacert ${instance.ssl.ca} \
                      --cert ${instance.ssl.crt} \
                      --key ${instance.ssl.key} \
                      -h ${kv.host} -p ${builtins.toString kv.port} \
                      --user ${instance.user} \
                      "$@"
                  '';
                };
              in
              {
                toh.meta.kv.apps.${app} = {
                  inherit prefix;
                  database = "none";
                };

                environment.systemPackages = [ clients.${kv.protocol} ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-kv SET ${key} ${value} | grep -qx OK", timeout=300)
              client.wait_until_succeeds("contract-kv GET ${key} | grep -qx ${value}", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
