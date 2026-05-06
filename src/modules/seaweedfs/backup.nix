{
  toh.lib.nixosModules.services-seaweedfs-backup =
    {
      pkgs,
      lib,
      tohLib,
      config,
      ...
    }:
    let
      machines = tohLib.serviceMachines "seaweedfs";

      filers = builtins.concatStringsSep "," (
        builtins.map (
          machine:
          machine.config.services.seaweedfs.filers.toh.ip
          + ":"
          + (builtins.toString machine.config.services.seaweedfs.filers.toh.httpPort)
        ) machines
      );

      mkMachineShell =
        machine:
        if machine.name == config.toh.meta.machine.name then
          ""
        else
          ''ssh -o "StrictHostKeyChecking no" -o "UserKnownMachinesFile /dev/null"'';

      mkMachineRsyncShell =
        machine:
        if machine.name == config.toh.meta.machine.name then "" else "-e '${mkMachineShell machine}' ";

      mkMachineSshShell =
        machine:
        if machine.name == config.toh.meta.machine.name then
          ""
        else
          "${mkMachineShell machine} ${machine.meta.network.ip}";

      mkMachineSource =
        machine:
        if machine.name == config.toh.meta.machine.name then
          "${machine.system.services.seaweedfs.volumes.toh.dataDir}/"
        else
          "${machine.meta.network.ip}:${machine.system.services.seaweedfs.volumes.toh.dataDir}/";

      mkMachineOwnerGroup =
        machine:
        machine.system.services.seaweedfs.volumes.toh.user
        + ":"
        + machine.system.services.seaweedfs.volumes.toh.group;

      stateDir = config.services.seaweedfs.filers.toh.stateDir;
      backupDirRelative = "toh/backup/logical";
      backupDir = "${stateDir}/extern/${backupDirRelative}";
      mountDirRelative = "toh/backup/mount";
      mountDir = "${stateDir}/extern/${mountDirRelative}";
      cacheDirRelative = "toh/backup/cache";
      cacheDir = "${stateDir}/extern/${cacheDirRelative}";

      user = config.services.seaweedfs.filers.toh.user;
      group = config.services.seaweedfs.filers.toh.group;

      dataDir = "./seaweedfs";

      logicalBackupPackage = pkgs.writeShellApplication {
        name = "seaweedfs-logical-backup";
        runtimeInputs = [
          pkgs.util-linux
        ];
        text = ''
          rm -rf "${backupDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${backupDir}"
          rm -rf "${mountDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${mountDir}"
          rm -rf "${cacheDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${cacheDir}"

          systemd-run --unit seaweedfs-logical-backup-mount weed mount \
            -dir '${mountDir}' \
            -cacheDir '${cacheDir}' \
            -filer '${filers}' \
            -filer.path '/'
          systemctl is-active seaweedfs-logical-backup-mount
          while ! mountpoint -q "${mountDir}"; do
            sleep 1
          done
          shopt -s tohglob
          cp -a "${mountDir}/"* "${backupDir}"
          shopt -u tohglob
          systemctl stop seaweedfs-logical-backup-mount
          umount "${mountDir}" || true
          fusermount -u "${mountDir}" || true
          fusermount3 -u "${mountDir}" || true
          while mountpoint -q "${mountDir}"; do
            umount "${mountDir}" || true
            fusermount -u "${mountDir}" || true
            fusermount3 -u "${mountDir}" || true
          done
          ls -la "${mountDir}"

          mv "${backupDir}" "${dataDir}"
          chown -R "$(id -un):$(id -gn)" "${dataDir}"

          rm -rf "${mountDir}"
          rm -rf "${cacheDir}"
        '';
      };

      logicalRestorePackage = pkgs.writeShellApplication {
        name = "seaweedfs-logical-restore";
        runtimeInputs = [
          pkgs.util-linux
        ];
        text = ''
          rm -rf "${backupDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "$(dirname "${backupDir}")"
          rm -rf "${mountDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${mountDir}"
          rm -rf "${cacheDir}"
          runuser -u "${user}" -g "${group}" -- mkdir -p "${cacheDir}"

          mv "${dataDir}" "${backupDir}"
          chown -R "${user}:${group}" "${backupDir}"

          systemd-run --unit seaweedfs-logical-restore-mount weed mount \
            -dir '${mountDir}' \
            -cacheDir '${cacheDir}' \
            -filer '${filers}' \
            -filer.path '/'
          systemctl is-active seaweedfs-logical-restore-mount
          while ! mountpoint -q "${mountDir}"; do
            sleep 1
          done
          shopt -s tohglob
          mv "${backupDir}/"* "${mountDir}"
          shopt -u tohglob
          systemctl stop seaweedfs-logical-restore-mount
          umount "${mountDir}" || true
          fusermount -u "${mountDir}" || true
          fusermount3 -u "${mountDir}" || true
          while mountpoint -q "${mountDir}"; do
            umount "${mountDir}" || true
            fusermount -u "${mountDir}" || true
            fusermount3 -u "${mountDir}" || true
          done
          ls -la "${mountDir}"

          rm -rf "${backupDir}"
          rm -rf "${mountDir}"
          rm -rf "${cacheDir}"
        '';
      };

      physicalBackupPackage = pkgs.writeShellApplication {
        name = "seaweedfs-physical-backup";
        runtimeInputs = [
          pkgs.openssh
          pkgs.rsync
        ];
        text = ''
          backupDir="./seaweedfs"
          mkdir -p "$backupDir"

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-filer@toh.service"
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-volume@toh.service"
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-master.service"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            mkdir -p "$backupDir/${machine.name}"
            rsync -avz --delete ${mkMachineRsyncShell machine} \
              "${mkMachineSource machine}" \
              "$backupDir/${machine.name}/" \
              --chown "$(id -un):$(id -gn)"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl start "seaweedfs-master.service"
            ${mkMachineSshShell machine} systemctl start "seaweedfs-volume@toh.service"
            ${mkMachineSshShell machine} systemctl start "seaweedfs-filer@toh.service"
          '') machines}
        '';
      };

      physicalRestorePackage = pkgs.writeShellApplication {
        name = "seaweedfs-physical-restore";
        runtimeInputs = [
          pkgs.openssh
          pkgs.rsync
          pkgs.systemd
        ];
        text = ''
          backupDir="./seaweedfs"

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-filer@toh.service"
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-volume@toh.service"
            ${mkMachineSshShell machine} systemctl stop "seaweedfs-master.service"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            rsync -avz --delete ${mkMachineRsyncShell machine} \
              "$backupDir/${machine.name}/" \
              "${mkMachineSource machine}" \
              --chown "${mkMachineOwnerGroup machine}"
          '') machines}

          ${lib.concatMapStringsSep "\n" (machine: ''
            ${mkMachineSshShell machine} systemctl start "seaweedfs-master.service"
            ${mkMachineSshShell machine} systemctl start "seaweedfs-volume@toh.service"
            ${mkMachineSshShell machine} systemctl start "seaweedfs-filer@toh.service"
          '') machines}
        '';
      };
    in
    lib.mkIf config.toh.services.seaweedfs.enable {
      toh.backup.physical.files = [ (lib.getExe physicalBackupPackage) ];
      toh.restore.physical.files = [ (lib.getExe physicalRestorePackage) ];
      toh.backup.logical.files = [ (lib.getExe logicalBackupPackage) ];
      toh.restore.logical.files = [ (lib.getExe logicalRestorePackage) ];
    };
}
