{ selfLib, ... }:

# NOTE: every member of a vpn runs the implementation, so this contract has no
# separate client and the members check each other; network picks one of the
# layouts in ./vpn

{
  self.lib.test.testModules.contracts-vpn =
    { lib, config, ... }:
    let
      cfg = config.toh.test.contracts.vpn;
    in
    {
      options.toh.test.contracts.vpn = selfLib.test.contract.options "vpn" cfg // {
        network = lib.mkOption {
          type = lib.types.enum [
            "mesh"
            "relay"
          ];
          description = ''
            `mesh` puts every member on one network, `relay` puts two members
            in homes behind NAT routers and a third on the internet between
            them.
          '';
        };

        mode = lib.mkOption {
          type = lib.types.enum [
            "proxy"
            "punch"
          ];
          default = "proxy";
          description = ''
            For the relay network: `proxy` checks that the homes talk through
            the relay when they cannot reach each other, `punch` that they
            reach each other directly through their NATs once the relay
            introduced them.
          '';
        };

        stun = lib.mkOption {
          type = lib.types.bool;
          default = false;
          internal = true;
          description = ''
            Whether the implementation needs a STUN server to punch through
            NAT. The implementation turns it on and reads `stunServers`.
          '';
        };

        stunServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          internal = true;
          description = "Addresses of the STUN server, when the test runs one";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.test.contracts.vpn.servers = lib.mkDefault 5;
      };
    };
}
