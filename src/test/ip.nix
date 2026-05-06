{
  toh.lib.test.testModules.ip =
    { lib, config, ... }:
    let
      cfg = config.toh.test.ip;
    in
    {
      options.toh.test = {
        ip = {
          enable = lib.mkEnableOption "IP test server";
        };
      };

      config = lib.mkIf cfg.enable {
        toh.test.http.ip = {
          domains = [
            "api.ipify.org"
            "api6.ipify.org"
            "api64.ipify.org"
            "icanhazip.com"
            "ipv4.icanhazip.com"
            "ipv6.icanhazip.com"
            "ifconfig.io"
            "ident.me"
            "v4.ident.me"
            "v6.ident.me"
            "ipinfo.io"
            "checkip.spdyn.de"
            "ipleak.net"
            "ip.nnev.de"
            "ip4.nnev.de"
            "ip6.nnev.de"
            "wtfismyip.com"
            "ipv4.wtfismyip.com"
            "ipv6.wtfismyip.com"
            "api.seeip.org"
            "ipv4.seeip.org"
            "ipv6.seeip.org"
            "ip.changeip.com"
          ];

          handler = ''
            host = headers.get('Host', ''').lower()

            def get_client_ip():
              client_addr = self.client_address[0]
              if client_addr.startswith('::ffff:'):
                return client_addr[7:]
              return client_addr

            def get_ipv4():
              ip = get_client_ip()
              if '.' in ip and ':' not in ip:
                return ip
              return None

            def get_ipv6():
              ip = get_client_ip()
              if ':' in ip and not ip.startswith('::ffff:'):
                return ip
              return None

            ip = "127.0.0.1"

            if 'api.ipify.org' in host:
              ip = get_ipv4() or get_client_ip()
              response = ip
            elif 'api6.ipify.org' in host:
              ip = get_ipv6() or get_client_ip()
              response = ip
            elif 'api64.ipify.org' in host:
              ip = get_client_ip()
              response = ip

            elif host == 'icanhazip.com' or 'ipv4.icanhazip.com' in host:
              ip = get_ipv4() or get_client_ip()
              response = ip
            elif 'ipv6.icanhazip.com' in host:
              ip = get_ipv6() or get_client_ip()
              response = ip

            elif 'ifconfig.io' in host:
              if path == '/ip' or path == '/':
                ip = get_client_ip()
                response = ip

            elif 'ident.me' in host:
              if 'v4.ident.me' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'v6.ident.me' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip
              else:
                ip = get_client_ip()
                response = ip

            elif 'ipinfo.io' in host:
              if path == '/ip' or path == '/':
                ip = get_client_ip()
                response = ip

            elif 'checkip.spdyn.de' in host:
              ip = get_client_ip()
              response = ip

            elif 'ipleak.net' in host:
              ip = get_client_ip()
              content_type = 'application/json'
              response = json.dumps({
                "ip": ip,
                "type": "ipv4" if '.' in ip else "ipv6"
              })

            elif 'ip.nnev.de' in host:
              if 'ip4.nnev.de' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'ip6.nnev.de' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip
              else:
                ip = get_client_ip()
                response = ip

            elif 'wtfismyip.com' in host:
              if 'ipv4.wtfismyip.com' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'ipv6.wtfismyip.com' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip
              else:
                ip = get_client_ip()
                response = ip

            elif 'seeip.org' in host:
              if 'ipv4.seeip.org' in host:
                ip = get_ipv4() or get_client_ip()
                response = ip
              elif 'ipv6.seeip.org' in host:
                ip = get_ipv6() or get_client_ip()
                response = ip
              else:
                ip = get_client_ip()
                response = ip

            elif 'changeip.com' in host:
              ip = get_client_ip()
              response = ip

            else:
              ip = get_client_ip()
              response = ip

            store["ips"] = store.get("ips", []) + [ip]
          '';
        };
      };
    };
}
