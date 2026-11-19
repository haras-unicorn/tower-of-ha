{ selfLib, ... }:

# NOTE: this contract runs without the dns helper, and the client asks with
# dig, which skips /etc/hosts, so the answer comes from the implementation

{
  self.lib.test.testModules.contracts-dns =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.dns;

      clientMeta = machines.client.toh.meta;
      serverMeta = machines.server1.toh.meta;
      nodeName = "${serverMeta.machine.name}.${clientMeta.domains.node}";
      expected = serverMeta.network.ip;
    in
    {
      options.toh.test.contracts.dns = selfLib.test.contract.options "dns" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names = { };
            dnsHelper = false;
            client =
              { pkgs, ... }:
              let
                contract = pkgs.writeShellApplication {
                  name = "contract-dns";
                  runtimeInputs = [ pkgs.dig ];
                  text = ''
                    dig +short A "$1"
                  '';
                };
              in
              {
                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-dns ${nodeName} | grep -qx '${expected}'", timeout=300)
            '';
          }
        ]
      );
    };
}
