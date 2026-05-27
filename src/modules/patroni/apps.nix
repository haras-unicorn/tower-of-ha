{
  toh.lib.nixosModules.services-patroni-apps =
    {
      lib,
      config,
      tohLib,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.patroni;

      anyMachines = tohLib.anyServiceMachines "patroni";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
            dbUser = config.toh.services.patroni.users.${name};
          }
        ) (lib.attrsToList apps);

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.database.apps) config.toh.cluster.machinea
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.database.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));
    in
    {
      toh.meta.database.instances = mergeByMachineApps (
        { name, dbUser, ... }:
        {
          ${name} = {
            password = dbUser.password;
            parameters = {
              sslmode = "verify-full";
              sslrootcert = dbUser.ca;
              sslcert = dbUser.crt;
              sslkey = dbUser.key;
            };
            ssl.ca = dbUser.ca;
            ssl.crt = dbUser.crt;
            ssl.key = dbUser.key;
            url = dbUser.url;
          };
        }
      );

      toh.services.patroni.init.sql.files = mergeByClusterApps (
        app:
        lib.mkIf (app.init.sql.file != null) [
          {
            ${app.name} = pkgs.writeText "${app.name}-patroni-init-file" ''
              \c ${app.name}

              ${builtins.readFile app.init.sql.file}
            '';
          }
        ]
      );
      toh.services.patroni.init.sql.scripts = mergeByClusterApps (
        app:
        lib.mkIf (app.init.sql.script != null) [
          {
            ${app.name} = ''
              \c ${app.name}

              ${app.init.sql.script}
            '';
          }
        ]
      );
      toh.services.patroni.init.nushell.files = mergeByClusterApps (
        app:
        lib.mkIf (app.init.nushell.file != null) [
          {
            ${app.name} = app.init.nushell.file;
          }
        ]
      );
      toh.services.patroni.init.nushell.scripts = mergeByClusterApps (
        app:
        lib.mkIf (app.init.nushell.script != null) [
          {
            ${app.name} = app.init.nushell.script;
          }
        ]
      );
      toh.services.patroni.init.systemd.units = mergeByClusterApps (
        app:
        lib.mkIf (app.init.systemd.unit != null) [
          {
            ${app.name} = app.init.systemd.unit;
          }
        ]
      );

      toh.services.patroni.users = mergeByClusterApps (
        {
          name,
          user,
          group,
          ...
        }:
        {
          ${name} = {
            inherit user group;
            installSecrets = true;
          };
        }
      );
    };
}
