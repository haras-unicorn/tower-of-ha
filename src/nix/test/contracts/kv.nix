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
            '';
          }
        ]
      );
    };
}
