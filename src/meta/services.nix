{
  toh.lib.nixosModules.meta-services =
    {
      config,
      lib,
      tohLib,
      ...
    }:
    let
      baseEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              default = config.toh.meta.network.ip;
              description = "Endpoint host";
            };

            port = lib.mkOption {
              type = lib.types.port;
              description = "Endpoint port";
            };
          };
        };

      secureEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            ssl = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Turn on SSL for this endpoint";
            };
          };
        };

      terminatedEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            sslTermination = lib.mkOption {
              type = lib.types.enum tohLib.services.sslTermination;
              default = "terminate";
              description = ''
                Turn on SSL termination for this endpoint:
                - re-encrypt: the frontend uses its own certificate to decrypt packets
                  before re-encrypting them to the backend
                - terminate: the frontend uses its own certificate to decrypt packets
                  and sends them unencrypted to the backend
                - passthrough: the fronted just passes packets to the backend
                  whether encrypted or unencrypted
              '';
            };
          };
        };

      layer4EndpointSubmodule =
        { lib, ... }:
        {
          options = {
            layer7Protocol = lib.mkOption {
              type = lib.types.enum tohLib.services.layer7Protocols;
              description = "Layer 7 protocol on top of this layer 4 proxy";
            };
          };
        };

      httpEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            path = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "HTTP-based endpoint path";
            };
          };
        };

      httpHealthEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            method = lib.mkOption {
              type = lib.types.str;
              default = "GET";
              description = "HTTP-based health endpoint method";
            };
            status = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 200;
              description = "HTTP-based health endpoint expected status";
            };
          };
        };

      makeEndpointSubmodule =
        {
          makeExtraEndpointImports ? (_: [ ]),
          extraTags ? (_: { }),
          endpointNullable ? false,
        }@attrs:
        { lib, ... }:
        {
          options = {
            endpoint =
              lib.mkOption {
                description = "Server endpoint";
                type = (if endpointNullable then lib.types.nullOr else lib.id) (
                  lib.types.attrTag (
                    {
                      tcp = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "tcp";
                        };
                        default = { };
                        description = "TCP endpoint";
                      };
                      http = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                            httpEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "http";
                        };
                        default = { };
                        description = "HTTP endpoint";
                      };
                      https = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                            httpEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "https";
                        };
                        default = { };
                        description = "HTTPS endpoint";
                      };
                    }
                    // (extraTags attrs)
                  )
                );
              }
              // (if endpointNullable then { default = null; } else { });
          };
        };

      makeExtraSecureEndpointSubmodules =
        protocol: if protocol == "tcp" then [ terminatedEndpointSubmodule ] else [ ];

      makeExtraSecureHealthEndpointSubmodules =
        protocol: if protocol == "tcp" then [ secureEndpointSubmodule ] else [ ];

      makeExtraLayer4EndpointSubmodules =
        protocol:
        if protocol == "tcp" then
          [
            layer4EndpointSubmodule
            { layer7Protocol = lib.mkDefault protocol; }
          ]
        else
          [ ];

      makeExtraHealthHttpEndpointSubmodules =
        protocol:
        if
          builtins.elem protocol [
            "http"
            "https"
          ]
        then
          [ httpHealthEndpointSubmodule ]
        else
          [ ];
    in
    {
      config = {
        toh.lib = {
          services = {
            endpoint = {
              toAttrs =
                endpoint:
                let
                  protocol = builtins.head (builtins.attrNames endpoint);
                in
                endpoint.${protocol} // { inherit protocol; };

              toUrl =
                endpoint:
                let
                  attrs = tohLib.services.endpoint.toAttrs endpoint;

                  host = attrs.host;
                  port = attrs.port;
                  protocol = if attrs ? layer7Protocol then attrs.layer7Protocol else attrs.protocol;
                  base =
                    {
                      user ? null,
                      password ? null,
                      path ? null,
                      parameters ? null,
                    }:
                    tohLib.url.makeUrl {
                      inherit
                        protocol
                        user
                        password
                        host
                        port
                        path
                        parameters
                        ;
                    };
                in
                if
                  builtins.elem attrs.protocol [
                    "http"
                    "https"
                  ]
                then
                  {
                    path ? null,
                    query ? { },
                  }:
                  base {
                    path = tohLib.url.makePath {
                      basePath = attrs.path or null;
                      relativePath = path;
                    };
                    parameters = query;
                  }
                else if
                  builtins.elem attrs.protocol [
                    "postgresql"
                    "mysql"
                  ]
                then
                  {
                    user,
                    password,
                    database,
                    parameters ? { },
                  }:
                  base {
                    inherit user password parameters;
                    path = database;
                  }
                else
                  base { };
            };
          };
        };
      };

      options.toh.meta = {
        relays = lib.mkOption {
          description = "Addresses of reverse proxies";
          default = [ ];
          type = lib.types.listOf lib.types.str;
        };

        services = lib.mkOption {
          description = "Service registration for proxying via DNS + reverse proxy";
          default = { };
          type = lib.types.attrsOf (
            lib.types.submodule (
              { config, ... }:
              let
                endpointAttrs = tohLib.services.endpoint.toAttrs config.endpoint;

                healthDefaultEndpoint =
                  if endpointAttrs.protocol == "tcp" then
                    (builtins.removeAttrs endpointAttrs [
                      "protocol"
                      "sslTermination"
                    ])
                    // {
                      ssl = endpointAttrs.sslTermination == "re-encrypt";
                    }
                  else
                    builtins.removeAttrs endpointAttrs [ "protocol" ];
              in
              {
                imports = [
                  (makeEndpointSubmodule {
                    makeExtraEndpointImports =
                      protocol: makeExtraSecureEndpointSubmodules protocol ++ makeExtraLayer4EndpointSubmodules protocol;
                  })
                ];

                options = {
                  health = lib.mkOption {
                    default = { };
                    description = "Service health";
                    type = lib.types.submodule {
                      imports = [
                        (makeEndpointSubmodule {
                          endpointNullable = true;
                          makeExtraEndpointImports =
                            protocol:
                            makeExtraSecureHealthEndpointSubmodules protocol
                            ++ makeExtraLayer4EndpointSubmodules protocol
                            ++ makeExtraHealthHttpEndpointSubmodules protocol;
                        })
                      ];
                    };
                  };
                };

                config = {
                  health = {
                    endpoint = lib.mkDefault {
                      ${endpointAttrs.protocol} = healthDefaultEndpoint;
                    };
                  };
                };
              }
            )
          );
        };

        proxies = lib.mkOption {
          description = "Proxies to services available via DNS + reverse proxy";
          default = { };
          type = lib.types.attrsOf (
            lib.types.submodule {
              imports = [
                (makeEndpointSubmodule {
                  extraTags =
                    {
                      makeExtraEndpointImports ? (_: [ ]),
                      ...
                    }:
                    {
                      postgresql = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "postgresql";
                        };
                        default = { };
                        description = "PostgreSQL endpoint";
                      };
                      mysql = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "mysql";
                        };
                        default = { };
                        description = "MySQL endpoint";
                      };
                    };
                })
              ];
            }
          );
        };
      };
    };
}
