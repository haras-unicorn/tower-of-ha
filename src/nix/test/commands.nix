{ selfLib, ... }:

{
  self.lib.test.testModules.commands =
    {
      specialArgs,
      config,
      lib,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.commands;

      textType = selfLib.types.testCommand;
    in
    {
      options.toh.test = {
        commands = {
          enable = (lib.mkEnableOption "Test commands") // {
            default = true;
          };

          helpers = lib.mkOption {
            type = lib.types.listOf textType;
            default = [ ];
            description = ''
              Python definitions that the other test commands may use, like
              the faults; they run first, after the machines start
            '';
          };

          prefix = lib.mkOption {
            type = textType;
            default = "";
            description = "Test script prefix";
          };

          perNodeInCluster = lib.mkOption {
            type = lib.types.attrsOf (lib.types.listOf textType);
            default = { };
            description = ''
              Test script commands that are executed like for each node in the cluster:

              (c1-n1)
              (c1-n2)
              (c1-n3)
              ...

              (c2-n1)
              (c2-n2)
              (c2-n3)
              ...

              ...
            '';
          };

          perNode = lib.mkOption {
            type = lib.types.listOf textType;
            default = [ ];
            description = ''
              Test script commands that are executed like for each node:

              (c1-n1)
              (c1-n2)
              (c1-n3)
              ...

              (c2-n1)
              (c2-n2)
              (c2-n3)
              ...

              ...
            '';
          };

          suffix = lib.mkOption {
            type = textType;
            default = "";
            description = "Test script suffix";
          };

          checks = lib.mkOption {
            type = lib.types.listOf textType;
            default = [ ];
            description = "Test script commands that run after the suffix, like the checks of the invariants";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        testScript =
          let
            makeArgs =
              nodes:
              specialArgs
              // {
                inherit lib;
                inherit nodes;
                machineList = builtins.attrValues nodes;
              };

            evaluateText =
              defaultArg: args: evaluatesToText:
              let
                evaluatesToTextCalled =
                  if lib.isFunction evaluatesToText then
                    if lib.functionArgs evaluatesToText == { } then evaluatesToText defaultArg else evaluatesToText args
                  else
                    evaluatesToText;
              in
              if builtins.isList evaluatesToTextCalled then
                builtins.concatStringsSep "\n" evaluatesToTextCalled
              else
                evaluatesToTextCalled;

            evaluateCluster =
              nodes: commands:
              builtins.concatStringsSep "\n" (
                builtins.concatMap (
                  command:
                  (builtins.map (node: ''
                    command_node = ${node.toh.meta.machine.name}
                    ${evaluateText node (
                      (makeArgs nodes)
                      // {
                        inherit node;
                      }
                    ) command}
                  '') (builtins.attrValues nodes))
                ) commands
              );

            helpers = builtins.concatStringsSep "\n" (
              builtins.map (evaluateText machines (makeArgs machines)) cfg.helpers
            );

            prefix = evaluateText machines (makeArgs machines) cfg.prefix;

            perNodeInCluster = builtins.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: perNode:
                evaluateCluster (lib.filterAttrs (machine: _: lib.hasPrefix name machine) machines) perNode
              ) cfg.perNodeInCluster

            );

            perNode = evaluateCluster machines cfg.perNode;

            suffix = evaluateText machines (makeArgs machines) cfg.suffix;

            checks = builtins.concatStringsSep "\n" (
              builtins.map (evaluateText machines (makeArgs machines)) cfg.checks
            );
          in
          ''
            start_all()

            #### Test commands helpers
            print("Defining test commands helpers...")

            ${helpers}


            #### Test commands prefix
            print("Running test commands prefix...")

            ${prefix}


            #### Test commands content
            print("Running test commands content...")

            ${perNodeInCluster}

            ${perNode}


            #### Test commands suffix
            print("Running test commands suffix...")

            ${suffix}


            #### Test commands checks
            print("Running test commands checks...")

            ${checks}
          '';
      };
    };
}
