{
  toh.lib.nixosModules.services-cockroachdb-backup =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      cfg = config.toh.services.cockroachdb;

      stateDirRelative = config.systemd.services.cockroachdb.serviceConfig.StateDirectory;
      stateDir = "/var/lib/${stateDirRelative}";
      backupDirRelative = "toh/backup/logical";
      backupDir = "${stateDir}/extern/${backupDirRelative}";

      dataDir = "./cockroachdb";

      user = config.services.cockroachdb.user;
      group = config.services.cockroachdb.group;

      machines = tohLib.serviceMachines "cockroachdb";

      mkMachineShell =
        machine:
        if machine.name == config.toh.machine.name then
          ""
        else
          ''ssh -o "StrictHostKeyChecking no" -o "UserKnownMachinesFile /dev/null"'';

      mkMachineRsyncShell =
        machine: if machine.name == config.toh.machine.name then "" else "-e '${mkMachineShell machine}' ";

      mkMachineSshShell =
        machine:
        if machine.name == config.toh.machine.name then
          ""
        else
          "${mkMachineShell machine} ${machine.meta.network.ip}";

      mkMachineSource =
        machine:
        if machine.name == config.toh.machine.name then
          "/var/lib/${machine.system.systemd.services.cockroachdb.serviceConfig.StateDirectory}/"
        else
          "${machine.meta.network.ip}:/var/lib/${machine.system.systemd.services.cockroachdb.serviceConfig.StateDirectory}/";

      mkMachineOwnerGroup =
        machine: machine.system.services.cockroachdb.user + ":" + machine.system.services.cockroachdb.group;

      physicalBackupPackage = pkgs.writeShellApplication {
        name = "cockroachdb-physical-backup";
        runtimeInputs = [
          pkgs.openssh
          pkgs.rsync
        ];
        text = ''
          backupDir="./cockroachdb"
          mkdir -p "$backupDir"

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl stop "cockroachdb.service"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            mkdir -p "$backupDir/${machine.name}"
            rsync -avz --delete ${mkMachineRsyncShell machine} \
              "${mkMachineSource machine}" \
              "$backupDir/${machine.name}/" \
              --chown "$(id -un):$(id -gn)"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl start "cockroachdb.service"
          '') machines}
        '';
      };

      physicalRestorePackage = pkgs.writeShellApplication {
        name = "cockroachdb-physical-restore";
        runtimeInputs = [
          pkgs.openssh
          pkgs.rsync
          pkgs.systemd
        ];
        text = ''
          backupDir="./cockroachdb"

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl stop "cockroachdb.service"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            rsync -avz --delete ${mkMachineRsyncShell machine} \
              "$backupDir/${machine.name}/" \
              "${mkMachineSource machine}" \
              --chown "${mkMachineOwnerGroup machine}"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl start "cockroachdb.service"
          '') machines}
        '';
      };

      logicalBackupPackage = pkgs.writeShellApplication {
        name = "cockroachdb-logical-backup";
        runtimeInputs = [
          pkgs.util-linux
        ];
        text = ''
          rm -rf "${backupDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${backupDir}"

          toh cockroachdb root sql \
            -e "BACKUP INTO 'nodelocal://self/${backupDirRelative}';"

          mv "${backupDir}" "${dataDir}"
          chown -R "$(id -un):$(id -gn)" "${dataDir}"
        '';
      };

      logicalRestorePackage = pkgs.writeShellApplication {
        name = "cockroachdb-logical-restore";
        runtimeInputs = [
          pkgs.util-linux
        ];
        text = ''
          rm -rf "${backupDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "$(dirname "${backupDir}")"
          mv "${dataDir}" "${backupDir}"
          chown -R "${user}:${group}" "${backupDir}"

          toh cockroachdb root sql -e "SHOW DATABASES;" | \
            awk 'NF>0 {print $1}' | \
            grep -Ev '^(system|defaultdb|postgres)$' | \
            tail -n +2 | \
            while read -r db; do
              toh cockroachdb root sql -e "DROP DATABASE \"$db\" CASCADE;"
          done

          toh cockroachdb root sql \
            -e "RESTORE FROM LATEST IN 'nodelocal://self/${backupDirRelative}';"

          rm -rf "${backupDir}"
        '';
      };
    in
    {
      config = lib.mkIf cfg.enable {
        toh.backup.physical.files = [ (lib.getExe physicalBackupPackage) ];
        toh.restore.physical.files = [ (lib.getExe physicalRestorePackage) ];
        toh.backup.logical.files = [ (lib.getExe logicalBackupPackage) ];
        toh.restore.logical.files = [ (lib.getExe logicalRestorePackage) ];
      };
    };
}
