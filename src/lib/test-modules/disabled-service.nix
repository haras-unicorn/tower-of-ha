{
  libAttrs.test.modules.disabled-service =
    { config, lib, ... }:
    let
      cfg = config.toh.test.disabledService;
    in
    {
      options.toh.test = {
        disabledService = {
          enable = lib.mkEnableOption "Test disabled service";

          name = lib.mkOption {
            type = lib.types.str;
            description = "Name of service";
          };

          module = lib.mkOption {
            type = lib.types.deferredModule;
            description = "Module for the test machine";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        nodes.machine = cfg.module;
        toh.test.commands.suffix = ''
          machine.fail("systemctl is-enabled ${cfg.name}");
        '';
      };
    };
}
