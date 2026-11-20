{
  self.nixosModules.meta-chat.flake = true;
  self.nixosModules.meta-chat.value =
    {
      lib,
      config,
      ...
    }:
    {
      options.toh.meta = {
        chat = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Chat server host (via proxy)";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 443;
            description = "Chat server port (via proxy)";
          };

          url = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = "https://${config.toh.meta.chat.host}:${builtins.toString config.toh.meta.chat.port}";
            defaultText = lib.literalExpression ''"https://''${config.toh.meta.chat.host}:''${builtins.toString config.toh.meta.chat.port}"'';
            description = "Chat server base URL (derived from host and port)";
          };

          apps = lib.mkOption {
            default = { };
            description = "App registration for ToH chat";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application chat secrets owner linux user";
                    };

                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Application chat secrets owner linux group";
                    };
                  };
                }
              )
            );
          };

          users = lib.mkOption {
            description = "Chat users of the apps on this machine, each with its own room";
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Chat user name, without the server";
                  };

                  password = lib.mkOption {
                    type = lib.types.path;
                    description = "Path to the chat user password";
                  };

                  room = lib.mkOption {
                    type = lib.types.str;
                    description = "Alias of the room of the user, with the server";
                  };
                };
              }
            );
          };
        };
      };
    };
}
