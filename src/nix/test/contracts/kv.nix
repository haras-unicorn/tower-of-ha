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
      # NOTE: any database but 0, where every connection starts, so the check
      # that the app cannot reach another database has one to try
      database = 1;

      # NOTE: refused with NOPERM; the client prints the refusal and may exit
      # with an error, so the exit code says nothing and the output is checked
      refused = command: ''
        output = client.succeed("contract-kv ${command} 2>&1 || true")
        assert "NOPERM" in output, output
      '';
      otherKey = "other:value";

      clientMeta = machines.client.toh.meta;
      host = clientMeta.kv.host;

      settle =
        lib.optionalString (cfg.replicationLag > 0)
          " && sleep ${builtins.toString (cfg.replicationLag + 1)}";

      # NOTE: a plain write, like the apps make; a store that replicates after
      # it answers can lose the writes of its last replicationLag seconds
      # with the primary, so the failover waits longer than that before it
      # kills a server, see docs/behavior.md
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "kv";
        write = ''lambda value: f"contract-kv SET ${prefix}{value} {value} | grep -qx OK${settle}"'';
        holds = ''lambda value: f"contract-kv GET ${prefix}{value} | grep -x {value}"'';
      };
    in
    {
      options.toh.test.contracts.kv = selfLib.test.contract.options "kv" cfg // {
        replicationLag = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          description = ''
            Seconds after it said yes to a write within which the store can
            still lose that write with its primary, 0 for a store that
            replicates before it answers
          '';
        };
      };

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
                      -n ${builtins.toString instance.database} \
                      --user ${instance.user} \
                      "$@"
                  '';
                };
              in
              {
                toh.meta.kv.apps.${app} = {
                  inherit prefix database;
                  # NOTE: with channels, so the ACL and not the missing
                  # permission is what refuses the channel of another app
                  permissions = [
                    selfLib.kv.permissions.read
                    selfLib.kv.permissions.write
                    selfLib.kv.permissions.keyspace
                    selfLib.kv.permissions.connection
                    selfLib.kv.permissions.pubsub
                  ];
                };

                environment.systemPackages = [ clients.${kv.protocol} ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-kv SET ${key} ${value} | grep -qx OK", timeout=300)
              client.wait_until_succeeds("contract-kv GET ${key} | grep -qx ${value}", timeout=30)
              client.succeed("contract-kv PUBLISH ${prefix}channel ${value} | grep -qx 0")
              ${refused "SET ${otherKey} ${value}"}
              ${refused "GET ${otherKey}"}
              ${refused "PUBLISH other:channel ${value}"}
              ${refused "SELECT 0"}
              ${refused "MOVE ${key} 0"}
              ${refused "ACL SETUSER ${app} allkeys"}
              ${refused "CONFIG GET maxmemory"}
              ${refused "FLUSHALL"}

              ${failover}
            '';
          }
        ]
      );
    };
}
