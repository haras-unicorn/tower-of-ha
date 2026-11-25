{ selfLib, ... }:

# NOTE: an oidc login needs a user and a browser, so the contract checks what
# a client can do on its own with any standard provider: read the discovery
# document of its issuer, and push an authorization request (rfc 9126), which
# the provider only takes from a registered client with the right secret

{
  self.lib.test.testModules.contracts-oidc =
    {
      lib,
      config,
      machines,
      ...
    }:
    let
      cfg = config.toh.test.contracts.oidc;

      app = selfLib.test.contract.app;
      state = "contract-state";

      clientMeta = machines.client.toh.meta;
      issuer = clientMeta.oidc.clients.${app}.issuerUrl;
      issuerHost = builtins.head (builtins.match "https://([^/:]+).*" issuer);

      # NOTE: what a provider keeps can only be read back through a login,
      # so the failover checks that it still takes the request of the app
      failover = selfLib.test.contract.failover {
        inherit cfg machines;
        capability = "oidc";
        write = "None";
        holds = ''lambda _: "contract-oidc"'';
      };
    in
    {
      options.toh.test.contracts.oidc = selfLib.test.contract.options "oidc" cfg;

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (selfLib.test.contract.base {
            inherit cfg;
            kind = config.toh.test.kind;
            names.${issuerHost} = clientMeta.relays;
            client =
              { config, pkgs, ... }:
              let
                client = config.toh.meta.oidc.clients.${app};
                redirectUri = "https://${app}.${config.toh.meta.domains.service}/callback";

                authorize = pkgs.writeShellApplication {
                  name = "contract-oidc-authorize";
                  runtimeInputs = [
                    pkgs.curl
                    pkgs.jq
                  ];
                  text = ''
                    issuer="${client.issuerUrl}"
                    issuer="''${issuer%/}"

                    discovery="$(curl --fail --silent --show-error \
                      "$issuer/.well-known/openid-configuration")"
                    advertised="$(jq -r .issuer <<<"$discovery")"
                    [ "''${advertised%/}" = "$issuer" ]

                    endpoint="$(jq -r .pushed_authorization_request_endpoint \
                      <<<"$discovery")"
                    secret="$(jq -Rr @uri < ${client.clientSecret})"

                    response="$(curl --fail --silent --show-error \
                      --config <(printf 'user = "%s:%s"\n' \
                        "${client.clientId}" "$secret") \
                      --data response_type=code \
                      --data client_id=${client.clientId} \
                      --data-urlencode redirect_uri=${redirectUri} \
                      --data scope=openid \
                      --data state=${state} \
                      "$endpoint")"
                    jq -e '.request_uri | startswith("urn:ietf:params:oauth:request_uri:")' \
                      <<<"$response"
                  '';
                };

                contract = pkgs.writeShellApplication {
                  name = "contract-oidc";
                  runtimeInputs = [ pkgs.util-linux ];
                  text = ''
                    exec setpriv --reuid=${app} --regid=${app} --init-groups \
                      ${lib.getExe authorize}
                  '';
                };
              in
              {
                toh.meta.oidc.apps.${app}.redirectUris = [ redirectUri ];

                toh.pki.installCa = true;

                environment.systemPackages = [ contract ];
              };
          })
          {
            toh.test.commands.suffix = ''
              client.wait_until_succeeds("contract-oidc", timeout=300)

              ${failover}
            '';
          }
        ]
      );
    };
}
