{ selfLib, ... }:

let
  providerTest =
    { config, lib, ... }:
    let
      cfg = config.toh.test.ddns-updater;

      domainSecret = "ddns-updater-${cfg.provider}-domain";

      secrets = {
        ${domainSecret} = cfg.domain;
      }
      // cfg.extraSecrets;
    in
    {
      options.toh.test = {
        ddns-updater = {
          provider = lib.mkOption {
            type = lib.types.str;
          };
          domain = lib.mkOption {
            type = lib.types.str;
          };
          extraSecrets = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
        };
      };

      config = {
        toh.test.dns.enable = true;
        toh.test.ddns.enable = true;
        toh.test.ip.enable = true;

        toh.test.cryl.cluster = [
          {
            ddns-updater = {
              generations = builtins.map (
                { name, value }:
                {
                  generator = "text";
                  arguments = {
                    inherit name;
                    text = value;
                  };
                }
              ) (lib.attrsToList secrets);
            };
          }
        ];

        containers.machine = {
          toh.pki.installCa = true;
          toh.meta.domains.machineSecret = domainSecret;
          toh.services.ddns-updater = {
            enable = true;
            ${cfg.provider}.enable = true;
          };
        };

        toh.test.commands.suffix =
          { nodes, ... }:
          ''
            machine.wait_for_unit("ddns-updater.service")

            http_ip.wait_until_succeeds("grep -q '${nodes.machine.toh.meta.network.ip}' /var/lib/http/log.jsonl", timeout=60)
            http_ip.wait_until_succeeds("grep -q '${nodes.machine.toh.meta.network.ip}' /var/lib/http/store.json", timeout=60)

            http_ddns.wait_until_succeeds("grep -q '${cfg.domain}' /var/lib/http/log.jsonl", timeout=180)
            http_ddns.wait_until_succeeds("grep -q '${cfg.domain}' /var/lib/http/store.json", timeout=60)
            http_ddns.wait_until_succeeds("grep -q '${nodes.machine.toh.meta.network.ip}' /var/lib/http/store.json", timeout=60)
          '';
      };
    };
in
{
  self.nixosTests.services-ddns-updater-duckdns = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    imports = [ providerTest ];
    toh.test.ddns-updater = {
      provider = "duckdns";
      domain = "test.duckdns.org";
      extraSecrets = {
        "ddns-updater-duckdns-token" = "1ef6dd59-eeb3-48c9-a42a-ef748e5246df";
      };
    };
  };

  self.nixosTests.services-ddns-updater-cloudflare = selfLib.test.makeNixosTest {
    toh.test.tier = 1;
    imports = [ providerTest ];
    toh.test.ddns-updater = {
      provider = "cloudflare";
      domain = "test.cloudflare.com";
      extraSecrets = {
        "ddns-updater-cloudflare-zone-identifier" = "id";
        "ddns-updater-cloudflare-token" = "1ef6dd59-eeb3-48c9-a42a-ef748e5246df";
      };
    };
  };
}
