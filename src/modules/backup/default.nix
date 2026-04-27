{
  toh.lib.nixosModules.programs-cli-backup =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.programs.cli;
      backupCfg = config.toh.backup;
      restoreCfg = config.toh.restore;
    in
    {
      options.toh.programs = {
        cli = {
          enableBackup = lib.mkEnableOption "ToH Backup CLI";
        };
      };

      config = lib.mkIf cfg.enableBackup {
        toh.overlays.cli-physical-backup = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [ pkgs.openssh ];
          loadExtraTextFromFile = ./backup.nu;
          extraTextVariables = {
            TOH_BACKUP_TYPE = "physical";
            TOH_BACKUP_COMMANDS = builtins.concatStringsSep "\n\n" (
              backupCfg.physical.files ++ backupCfg.physical.scripts
            );
          };
        };

        toh.overlays.cli-logical-backup = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [ pkgs.openssh ];
          loadExtraTextFromFile = ./backup.nu;
          extraTextVariables = {
            TOH_BACKUP_TYPE = "logical";
            TOH_BACKUP_COMMANDS = builtins.concatStringsSep "\n\n" (
              backupCfg.logical.files ++ backupCfg.logical.scripts
            );
          };
        };

        toh.overlays.cli-physical-restore = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [ pkgs.openssh ];
          loadExtraTextFromFile = ./restore.nu;
          extraTextVariables = {
            TOH_RESTORE_TYPE = "physical";
            TOH_RESTORE_COMMANDS = builtins.concatStringsSep "\n\n" (
              restoreCfg.physical.files ++ restoreCfg.physical.scripts
            );
          };
        };

        toh.overlays.cli-logical-restore = tohLib.cli.makeOverlay {
          extraRuntimeInputs = pkgs: [ pkgs.openssh ];
          loadExtraTextFromFile = ./restore.nu;
          extraTextVariables = {
            TOH_RESTORE_TYPE = "logical";
            TOH_RESTORE_COMMANDS = builtins.concatStringsSep "\n\n" (
              restoreCfg.logical.files ++ restoreCfg.logical.scripts
            );
          };
        };
      };
    };
}
