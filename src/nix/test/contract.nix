{ lib, selfLib, ... }:

let
  app = "contract";

  clientModule = client: {
    imports = [ client ];

    users.groups.${app} = { };
    users.users.${app} = {
      isSystemUser = true;
      group = app;
    };
  };
in
{
  self.lib.test.contract = {
    inherit app clientModule;

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
      {
        kind,
        cfg,
        names,
        client,
        dnsHelper ? true,
      }:
      lib.mkMerge [
        {
          toh.test.clusters.server = {
            amount = cfg.servers;
            module = cfg.server;
          };

          toh.test.dns.enable = dnsHelper;
          toh.test.dns.zones = builtins.mapAttrs (name: addresses: {
            ${name} = addresses;
          }) names;
        }
        (selfLib.test.ofKind kind {
          client = clientModule client;
        })
      ];

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
