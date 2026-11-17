{
  toh.lib.nixosModules.meta-oidc =
    { lib, tohLib, ... }:
    {
      options.toh.meta = {
        oidc = {
          issuer = lib.mkOption {
            type = lib.types.str;
            description = "OIDC issuer URL";
          };
          baseUrl = lib.mkOption {
            type = lib.types.str;
            description = "OIDC provider base URL";
          };
          apps = lib.mkOption {
            default = { };
            description = "OIDC client app registration";
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    user = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "OIDC client secret owner linux user";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "OIDC client secret owner linux group";
                    };
                    redirectUris = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "OIDC client redirect URIs";
                    };
                    pkce = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "OIDC client PKCE";
                    };
                  };
                }
              )
            );
          };
          clients = lib.mkOption {
            default = { };
            description = "OIDC client credentials for consumers";
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  clientId = lib.mkOption {
                    type = lib.types.str;
                    description = "OIDC client ID";
                  };
                  clientSecret = lib.mkOption {
                    type = lib.types.str;
                    description = "OIDC client secret file path";
                  };
                  issuerUrl = lib.mkOption {
                    type = lib.types.str;
                    description = "OIDC issuer URL";
                  };
                  redirectUris = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "OIDC client redirect URIs";
                  };
                };
              }
            );
          };
        };
      };
    };
}
