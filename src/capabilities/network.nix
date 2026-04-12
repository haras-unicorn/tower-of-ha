{ config, ... }:

let
  common =
    { lib, ... }:
    {
      options.toh = {
        network = {
          subnet = {
            prefix = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet prefix.
              '';
            };
            ip = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet IP.
              '';
            };
            bits = lib.mkOption {
              type = lib.types.ints.u16;
              description = ''
                Network subnet bits.
              '';
            };
            mask = lib.mkOption {
              type = lib.types.str;
              description = ''
                Network subnet mask.
              '';
            };
          };
        };
      };
    };
in
{
  imports = [ common ];

  flake.nixosModules.capabilities-domains = {
    imports = [ common ];

    config.toh.network = config.toh.network;
  };
}
