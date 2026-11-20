{ selfLib, ... }:

{
  self.nixosModules.meta-services.flake = true;
  self.nixosModules.meta-services.value =
    {
      config,
      lib,
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
              type = lib.types.enum selfLib.services.sslTermination;
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
              type = lib.types.enum selfLib.services.layer7Protocols;
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

      tcpHealthEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            packets = lib.mkOption {
              description = "Packets to send and expect as part of the health check";
              default = [ ];
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    send = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Packet to send";
                    };
                    expect = lib.mkOption {
                      type = lib.types.nullOr selfLib.types.regexOrString;
                      default = null;
                      description = "Packet to expect";
                    };
                  };
                }
              );
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

      layer4PersistentEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            persistIp = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Persist connections over the same IP.";
            };
          };
        };

      httpPersistentEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            persistCookie = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "my_cookie";
              description = ''
                Persist connections that have the same cookie value
                of the provided cookie.
              '';
            };
          };
        };

      httpRouteEndpointSubmodule =
        { lib, ... }:
        {
          options = {
            route = lib.mkOption {
              default = null;
              description = ''
                Serve only some paths of the proxy address of another
                service, instead of an address of its own. A request that
                matches no route goes to the service itself.
              '';
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    service = lib.mkOption {
                      type = lib.types.str;
                      description = "The service whose proxy address this one serves paths of.";
                    };

                    priority = lib.mkOption {
                      type = lib.types.int;
                      default = 0;
                      description = ''
                        The routes of an address are tried from the
                        lowest number to the highest, and the first one
                        that matches takes the request. A negative number
                        wins over routes that leave it at 0, and a
                        positive one is a fallback for them. Routes with
                        the same number are tried by the name of their
                        service.
                      '';
                    };

                    paths = lib.mkOption {
                      description = ''
                        The paths the route takes. A request matches when
                        any of them does. A prefix is the start of the
                        path. A regular expression has to match the whole
                        path, without the query, and has to be valid for
                        every proxy, so it sticks to what RE2 accepts.
                      '';
                      type = lib.types.listOf (
                        lib.types.attrTag {
                          prefix = lib.mkOption {
                            type = lib.types.str;
                            description = "The start of the path.";
                          };
                          regex = lib.mkOption {
                            type = lib.types.str;
                            description = "A regular expression for the whole path.";
                          };
                        }
                      );
                    };
                  };
                }
              );
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
                      submit = lib.mkOption {
                        type = lib.types.submodule {
                          imports = [
                            baseEndpointSubmodule
                          ]
                          ++ makeExtraEndpointImports "submit";
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
        protocol:
        if
          builtins.elem protocol [
            "tcp"
            "submit"
          ]
        then
          [ terminatedEndpointSubmodule ]
        else
          [ ];

      makeExtraSecureHealthEndpointSubmodules =
        protocol:
        if
          builtins.elem protocol [
            "tcp"
            "submit"
          ]
        then
          [ secureEndpointSubmodule ]
        else
          [ ];

      makeExtraRouteEndpointSubmodules =
        protocol:
        if
          builtins.elem protocol [
            "http"
            "https"
          ]
        then
          [ httpRouteEndpointSubmodule ]
        else
          [ ];

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

      makeExtraHealthTcpEndpointSubmodules =
        protocol: if protocol == "tcp" then [ tcpHealthEndpointSubmodule ] else [ ];

      makePersistentEndpointSubmodules =
        protocol:
        if protocol == "tcp" then
          [ layer4PersistentEndpointSubmodule ]
        else if
          builtins.elem protocol [
            "http"
            "https"
          ]
        then
          [ httpPersistentEndpointSubmodule ]
        else
          [ ];
    in
    {
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
                endpointAttrs = selfLib.services.endpoint.toAttrs config.endpoint;

                healthDefaultEndpoint =
                  if endpointAttrs.protocol == "tcp" then
                    (builtins.removeAttrs endpointAttrs [
                      "protocol"
                      "sslTermination"
                      "persistIp"
                    ])
                    // {
                      ssl = endpointAttrs.sslTermination == "re-encrypt";
                    }
                  else
                    builtins.removeAttrs endpointAttrs [
                      "protocol"
                      "persistCookie"
                      "route"
                    ];
              in
              {
                imports = [
                  (makeEndpointSubmodule {
                    makeExtraEndpointImports =
                      protocol:
                      makeExtraSecureEndpointSubmodules protocol
                      ++ makeExtraLayer4EndpointSubmodules protocol
                      ++ makePersistentEndpointSubmodules protocol
                      ++ makeExtraRouteEndpointSubmodules protocol;
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
                            ++ makeExtraHealthTcpEndpointSubmodules protocol
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
                    (builtins.listToAttrs (
                      builtins.map (protocol: {
                        name = protocol;
                        value = lib.mkOption {
                          type = lib.types.submodule {
                            imports = [
                              baseEndpointSubmodule
                            ]
                            ++ makeExtraEndpointImports protocol;
                          };
                          default = { };
                          description = "${protocol} endpoint";
                        };
                      }) selfLib.services.extraLayer7Protocols
                    ));
                })
              ];
            }
          );
        };
      };
    };
}
