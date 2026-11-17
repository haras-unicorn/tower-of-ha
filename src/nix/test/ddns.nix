{
  toh.lib.test.testModules.ddns =
    { lib, config, ... }:
    let
      cfg = config.toh.test.ddns;
    in
    {
      options.toh.test = {
        ddns = {
          enable = lib.mkEnableOption "DDNS test server";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.test.http.ddns = {
          domains = [
            "duckdns.org"
            "www.duckdns.org"
            "api.cloudflare.com"
            "api.dynu.com"
            "api.dynv6.com"
            "api.dreamhost.com"
            "api.namecheap.com"
            "api.godaddy.com"
            "api.hetzner.cloud"
            "api.cloudns.net"
            "api.infomaniak.com"
            "api.porkbun.com"
            "api.gandi.net"
            "api.vultr.com"
            "api.linode.com"
            "api.desec.io"
            "api.domeneshop.no"
            "api.easydns.com"
            "api.freedns.afraid.org"
            "api.he.net"
            "api.inwx.com"
            "api.ionos.com"
            "api.loopia.com"
            "api.luadns.com"
            "api.myaddr.tools"
            "api.name.com"
            "api.netcup.de"
            "api.noip.com"
            "api.njalla.com"
            "api.ovh.com"
            "api.route53.amazonaws.com"
            "api.spdyn.de"
            "api.selfhost.de"
            "api.servercow.de"
            "api.strato.de"
            "api.variomedia.de"
            "api.zoneedit.com"
            "dyn.dns.he.net"
            "dyndns.strato.com"
            "nic.changeip.com"
            "dynupdate.no-ip.com"
            "dynupdate.ovh.com"
          ];
          handler = ''
            host = headers.get('Host', ''').lower()

            if 'cloudflare' in host:
              if body is not None and body != "":
                id = str(uuid.uuid4())
                json_body = json.loads(body)
                name = json_body.get('name', 'localhost')
                ip = json_body.get('content', '127.0.0.1')
                store[name] = {
                  'id': id,
                  'ip': ip
                }
                response = {
                  "success": True,
                  "errors": [],
                  "result": {
                    "id": id,
                    "content": ip,
                  }
                }
              else:
                name = params.get('domains', ['localhost'])[0]
                stored = store.get(name)
                if stored is not None:
                  response = {
                    "success": True,
                    "errors": [],
                    "result": [{
                      "id": stored['id'],
                      "content": stored['ip']
                    }]
                  }
                else:
                  response = {
                    "success": True,
                    "errors": [],
                    "result": []
                  }
              response = json.dumps(response)
              content_type = 'application/json'

            elif 'duckdns' in host:
              id = str(uuid.uuid4())
              name = params.get('domains', ['localhost'])[0]
              ip = params.get('ip', ['localhost'])[0]
              store[name] = {
                'id': id,
                'ip': ip
              }
              response = f'OK\n{ip}'
          '';
        };
      };
    };
}
