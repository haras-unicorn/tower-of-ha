{
  toh.lib.nixosModules.services-valkey-apps =
    {
      lib,
      config,
      tohLib,
      pkgs,
      ...
    }:
    let
      cfg = config.toh.services.valkey;

      anyMachines = tohLib.anyServiceMachines "valkey";

      appAttrsToList =
        apps:
        builtins.map (
          { name, value }:
          value
          // {
            inherit name;
            kvUser = config.toh.services.valkey.users.${name};
          }
        ) (lib.attrsToList apps);

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.kv.apps) config.toh.meta.cluster.machinea
        )
      );

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.kv.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));
    in
    {
      toh.meta.kv.instances = mergeByMachineApps (
        {
          name,
          kvUser,
          prefix,
          database,
          ...
        }:
        {
          ${name} = {
            password = kvUser.password;
            url = kvUser.url;
            prefix = lib.mkIf (prefix != "all" && prefix != "none") prefix;
            database = lib.mkIf (builtins.isInt database) database;
            ssl = {
              ca = kvUser.ca;
              crt = kvUser.crt;
              key = kvUser.key;
            };
            parameters = {
              ssl = "True";
              ssl_cert_reqs = "required";
              ssl_ca_path = kvUser.ca;
              ssl_certfile = kvUser.crt;
              ssl_keyfile = kvUser.key;
            }
            // lib.optionalAttrs (prefix != "all" && prefix != "none") {
              key_prefix = prefix;
            }
            // lib.optionalAttrs (builtins.isInt database) {
              db = database;
            };
          };
        }
      );

      # TODO: fix permission duplication here
      toh.services.valkey.users = lib.mkMerge [
        (mergeByMachineApps (
          {
            name,
            prefix,
            database,
            permissions,
            group,
            user,
            ...
          }:
          {
            ${name} = {
              installSecrets = true;
              inherit
                group
                user
                prefix
                database
                permissions
                ;
            };
          }
        ))
        (mergeByClusterApps (
          {
            name,
            prefix,
            database,
            permissions,
            group,
            user,
            ...
          }:
          {
            ${name} = {
              generateSecrets = true;
              inherit
                group
                user
                prefix
                database
                permissions
                ;
            };
          }
        ))
      ];
    };
}
