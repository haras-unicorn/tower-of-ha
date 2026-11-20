{ selfLib, ... }:

{
  self.nixosModules.services-patroni-apps.flake = true;
  self.nixosModules.services-patroni-apps.value =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.patroni;

      anyMachines = selfLib.cluster.anyServiceMachines config "patroni";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
            userSecrets = config.toh.services.patroni.users.${name};
          }
        ) (lib.attrsToList apps);

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.database.apps) config.toh.meta.cluster.machineList
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.database.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));

      appUser =
        secretsFlag:
        {
          name,
          user,
          group,
          dbName,
          dbUser,
          dbLocale,
          ...
        }:
        {
          ${name} = {
            inherit
              user
              group
              dbName
              dbUser
              dbLocale
              ;
            ${secretsFlag} = true;
          };
        };
    in
    {
      toh.meta.database.instances = mergeByMachineApps (
        {
          name,
          userSecrets,
          dbName,
          dbUser,
          ...
        }:
        {
          ${name} = {
            inherit dbName dbUser;
            password = userSecrets.password;
            parameters = {
              sslmode = "verify-full";
              sslrootcert = userSecrets.ca;
              sslcert = userSecrets.crt;
              sslkey = userSecrets.key;
            };
            ssl.ca = userSecrets.ca;
            ssl.crt = userSecrets.crt;
            ssl.key = userSecrets.key;
            url = userSecrets.url;
          };
        }
      );

      toh.services.patroni.init.sql.files = mergeByClusterApps (
        app:
        lib.mkIf (app.init.sql.file != null) [
          {
            ${app.name} = pkgs.writeText "${app.name}-patroni-init-file" ''
              \c ${app.dbName}
              SET ROLE ${app.dbUser};

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
              \c ${app.dbName}
              SET ROLE ${app.dbUser};

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

      toh.services.patroni.users = lib.mkMerge [
        (mergeByMachineApps (appUser "installSecrets"))
        (mergeByClusterApps (appUser "generateSecrets"))
      ];
    };
}
