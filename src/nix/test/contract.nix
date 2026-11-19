{ lib, ... }:

{
  self.lib.test.contract = {
    options = capability: cfg: {
      enable = lib.mkEnableOption "the ${capability} contract test";

      implementation = lib.mkOption {
        type = lib.types.attrTag (
          builtins.mapAttrs (
            name: module:
            lib.mkOption {
              type = lib.types.submodule module;
              description = "The ${name} implementation of the ${capability} capability";
            }
          ) cfg.implementationModules
        );
        description = "The ${capability} implementation under test";
      };

      implementationModules = lib.mkOption {
        type = lib.types.attrsOf lib.types.deferredModule;
        default = { };
        internal = true;
        description = ''
          The options of every ${capability} implementation, by tag. Each
          implementation adds its own from a test module.
        '';
      };

      server = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        internal = true;
        description = ''
          Module of every server. The picked implementation sets it to its
          service and whatever that service depends on.
        '';
      };

      servers = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Number of servers";
      };
    };

    base =
      { cfg, names }:
      {
        toh.test.clusters.server = {
          amount = cfg.servers;
          module = cfg.server;
        };

        toh.test.dns.enable = true;
        toh.test.dns.zones = builtins.mapAttrs (name: addresses: {
          ${name} = addresses;
        }) names;
      };

    implementation =
      {
        capability,
        implementation,
        server,
        test ? { },
      }:
      { config, ... }:
      let
        cfg = config.toh.test.contracts.${capability};
        picked = cfg.enable && cfg.implementation ? ${implementation};
      in
      {
        config = lib.mkMerge [
          {
            toh.test.contracts.${capability} = {
              implementationModules.${implementation} = { };
              server = lib.mkIf picked server;
            };
          }
          (lib.mkIf picked test)
        ];
      };
  };
}
