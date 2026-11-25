{ selfLib, ... }:

{
  self.lib.test.testModules.contracts-s3 =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.s3;

      app = selfLib.test.contract.app;
      object = "s3://${app}/value";
      value = "works";

      clientMeta = machines.client.toh.meta;
      host = clientMeta.s3.host;

      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "s3";
        write = ''lambda value: f"echo {value} | contract-s3 put - s3://${app}/{value}"'';
        holds = ''lambda value: f"contract-s3 get s3://${app}/{value} - | grep -x {value}"'';
      };
    in
    {
      options.toh.test.contracts.s3 = selfLib.test.contract.options "s3" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${host} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                s3 = config.toh.meta.s3;
                bucket = s3.buckets.${app};
                address = "${s3.host}:${builtins.toString s3.port}";

                clients.s3 = pkgs.writeShellApplication {
                  name = "contract-s3";
                  runtimeInputs = [
                    pkgs.s3cmd
                    pkgs.util-linux
                  ];
                  text = ''
                    AWS_ACCESS_KEY_ID="$(cat ${bucket.keyId})" \
                      AWS_SECRET_ACCESS_KEY="$(cat ${bucket.secretKey})" \
                      exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      s3cmd --ssl \
                      --host=${address} \
                      --host-bucket=${address} \
                      --region=${s3.region} \
                      "$@"
                  '';
                };
              in
              {
                toh.meta.s3.apps.${app} = { };

                toh.pki.installCa = true;

                environment.systemPackages = [ clients.${s3.protocol} ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("echo ${value} | contract-s3 put - ${object}", timeout=300)
              client.wait_until_succeeds("contract-s3 get ${object} - | grep -qx ${value}", timeout=30)

              ${failover}
            '';
          }
        ]
      );
    };
}
