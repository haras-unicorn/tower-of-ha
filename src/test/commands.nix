{
  toh.lib.test.testModules.commands =
    {
      specialArgs,
      config,
      lib,
      tohLib,
      nodes,
      nodea,
      ...
    }:
    let
      cfg = config.toh.test.commands;

      textType = tohLib.types.testCommand;
    in
    {
      options.toh.test = {
        commands = {
          enable = (lib.mkEnableOption "Test commands") // {
            default = true;
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
                nodea = builtins.attrValues nodes;
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

            prefix = evaluateText nodes (makeArgs nodes) cfg.prefix;

            perNodeInCluster = builtins.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: perNode: evaluateCluster (lib.filterAttrs (node: _: lib.hasPrefix name node) nodes) perNode
              ) cfg.perNodeInCluster

            );

            perNode = evaluateCluster nodes cfg.perNode;

            suffix = evaluateText nodes (makeArgs nodes) cfg.suffix;
          in
          ''
            start_all()

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
          '';
      };
    };
}
