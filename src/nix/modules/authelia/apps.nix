{
  toh.lib.nixosModules.services-authelia-apps =
    {
      lib,
      config,
      tohLib,
      ...
    }:
    let
      cfg = config.toh.services.authelia;

      name = "authelia";
      owner = name;
      group = name;

      proxyUrl = tohLib.services.endpoint.toUrl config.toh.meta.proxies.authelia.endpoint { };

      anyMachines = tohLib.anyServiceMachines "authelia";

      appAttrsToList =
        apps:
        lib.imap0 (
          index:
          { name, value }:
          value
          // {
            inherit name index;
          }
        ) (lib.attrsToList apps);

      mergeByClusterApps =
        forEachApp: lib.mkIf cfg.enable (lib.mkMerge (builtins.map forEachApp clusterApps));

      machineApps = appAttrsToList config.toh.meta.oidc.apps;

      mergeByMachineApps =
        forEachApp: lib.mkIf anyMachines (lib.mkMerge (builtins.map forEachApp machineApps));

      clusterApps = appAttrsToList (
        builtins.zipAttrsWith (_: builtins.head) (
          builtins.map (machine: machine.meta.oidc.apps) config.toh.meta.cluster.machinea
        )
      );
    in
    {
      toh.meta.oidc.clients = mergeByMachineApps (
        { name, redirectUris, ... }:
        {
          ${name} = {
            clientId = name;
            clientSecret = config.toh.meta.sops.secrets."authelia-oidc-${name}-secret-plaintext".path;
            issuerUrl = proxyUrl;
            inherit redirectUris;
          };
        }
      );

      services.authelia.instances.authelia = lib.mkIf cfg.enable {
        settings.identity_providers.oidc.clients = mergeByClusterApps (
          {
            name,
            redirectUris,
            pkce,
            ...
          }:
          [

            (lib.mkMerge [
              {
                client_id = name;
                client_name = name;
                client_secret = ''{{ secret "${
                  config.toh.meta.sops.secrets."authelia-oidc-${name}-secret".path
                }" }}'';
                public = false;
                redirect_uris = redirectUris;
                id_token_signed_response_alg = "ES256";
                scopes = [
                  "openid"
                  "profile"
                  "email"
                  "groups"
                  "offline_access"
                ];
                grant_types = [
                  "refresh_token"
                  "authorization_code"
                ];
                response_types = [ "code" ];
              }
              (lib.mkIf pkce {
                require_pkce = true;
                pkce_challenge_method = "S256";
              })
            ])
          ]
        );
      };

      toh.meta.sops.secrets = lib.mkMerge [
        (mergeByClusterApps (
          { name, ... }:
          {
            "authelia-oidc-${name}-secret" = {
              inherit owner group;
              mode = "0400";
            };
          }
        ))
        (mergeByMachineApps (
          { name, ... }@app:
          {
            "authelia-oidc-${name}-secret-plaintext" = {
              owner = app.user;
              group = app.group;
              mode = "0400";
            };

          }
        ))
      ];

      toh.meta.cryl.machine = lib.mkMerge [
        (mergeByClusterApps (
          { name, ... }:
          [
            {
              "authelia-${name}-secret" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-oidc-${name}-secret";
                      to = "authelia-oidc-${name}-secret";
                    };
                  }
                ];
              };
            }
          ]
        ))
        (mergeByMachineApps (
          { name, ... }:
          [
            {
              "authelia-${name}-secret-plaintext" = {
                generations = [
                  {
                    generator = "copy";
                    arguments = {
                      from = "cluster/authelia-oidc-${name}-secret-plaintext";
                      to = "authelia-oidc-${name}-secret-plaintext";
                    };
                  }
                ];
              };
            }
          ]
        ))
      ];

      toh.meta.cryl.cluster = mergeByClusterApps (
        { name, ... }:
        [
          {
            "authelia-${name}" = {
              generations = [
                {
                  generator = "password";
                  arguments = {
                    public = "authelia-oidc-${name}-secret";
                    private = "authelia-oidc-${name}-secret-plaintext";
                    length = 64;
                  };
                }
              ];
            };
          }
        ]
      );
    };
}
