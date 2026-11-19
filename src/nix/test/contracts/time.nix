{ selfLib, ... }:

# NOTE: the client is not a ToH time client: it asks every server of
# `toh.meta.time.servers` over plain NTP, which is all the contract promises;
# it uses chronyd in its query mode, which prints the offset and exits without
# setting the clock, and which skips a server that is not synchronized

{
  self.lib.test.testModules.contracts-time =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.time;

      kind = config.toh.test.kind;

      servers = machines.client.toh.meta.time.servers;

      queryTimeoutSeconds = 20;

      client =
        { pkgs, ... }:
        let
          contract = pkgs.writeShellApplication {
            name = "contract-time";
            runtimeInputs = [
              pkgs.chrony
              pkgs.gnugrep
            ];
            text = ''
              servers="${builtins.concatStringsSep " " servers}"
              [ -n "$servers" ]

              for server in $servers; do
                chronyd -Q -u root -t ${builtins.toString queryTimeoutSeconds} "server $server iburst" 2>&1 \
                  | grep -q 'System clock wrong by'
              done
            '';
          };
        in
        {
          environment.systemPackages = [ contract ];
        };
    in
    {
      options.toh.test.contracts.time = selfLib.test.contract.options "time" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg kind client;
            names = { };
            dnsHelper = false;
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-time", timeout=120)
            '';
          }
        ]
      );
    };
}
