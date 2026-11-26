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

    # NOTE: python that makes the faults of the test once on every server of
    # the contract, see fault_each in src/nix/test/faults.nix; write and
    # holds are python lambdas from a value to a command of the client, and
    # reader names the machine that runs holds instead of the client
    failover =
      {
        cfg,
        machines,
        capability,
        write,
        holds,
        reader ? "None",
      }:
      let
        servers = builtins.filter (lib.hasPrefix "server") (builtins.attrNames machines);
      in
      ''
        fault_each(
          client,
          [${builtins.concatStringsSep ", " servers}],
          "${cfg.online}",
          """${cfg.redundant}""",
          ${write},
          ${holds},
          reader=${reader},
        )
      '';

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

      online = lib.mkOption {
        type = lib.types.str;
        default = "toh-${capability}-online.target";
        description = ''
          Unit that is active on a server once the ${capability} runs there,
          which the failover waits for after it revives a server
        '';
      };

      redundant = lib.mkOption {
        type = lib.types.str;
        default = "true";
        description = ''
          Command that succeeds on a server once the ${capability} can lose
          any one server, like a database with a synchronous replica; the
          failover waits for it before it kills the next server
        '';
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
      { config, machines, ... }:
      let
        cfg = config.toh.test.contracts.${capability};
        picked = cfg.enable && cfg.implementation ? ${implementation};
        testConfig = if builtins.isFunction test then test { inherit config machines; } else test;
      in
      {
        config = lib.mkMerge [
          {
            toh.test.contracts.${capability} = {
              implementationModules.${implementation} = { };
              server = lib.mkIf picked server;
            };
          }
          (lib.mkIf picked testConfig)
          # NOTE: the failover of a contract makes every fault of the test
          # once on every server
          (lib.mkIf picked {
            toh.test.faults.amount = lib.mkDefault (builtins.length config.toh.test.faults.kinds * cfg.servers);
          })
        ];
      };
  };
}
