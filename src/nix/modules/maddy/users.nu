let users = r#'{{{TOH_MADDY_USERS}}}'# | from json

def --wrapped "main email" [user: string, ...args: string] {
  let config = $users | get $user

  let tmp = (mktemp -d)
  chmod 700 $tmp

  let password = if ($config.password | path exists) {
    if ($env.USER != root and $env.USER != $user) {
      sudo cat $config.password | str trim
    } else {
      open --raw $config.password | str trim
    }
  } else {
    let cluster = toh secrets cluster
    $cluster | get $"maddy-($user)-pass"
  }

  let machine = toh machine current

  let imap_proxy = $machine.meta.proxies."maddy-imap".endpoint.imap
  let domain = $machine.meta.email.domain
  let address = $"($user)@($domain)"

  let config = {
    downloads-dir: "/tmp"
    accounts: {
      ($address): {
        default: true
        email: $address
        display-name: $user
        backend: {
          type: "imap"
          host: $imap_proxy.host
          port: $imap_proxy.port
          encryption: {
            type: "tls"
          }
          login: $address
          auth: {
            type: "password"
            raw: $password
          }
        }
        message: {
          send: {
            backend: {
              type: "smtp"
              host: $domain
              port: 25
              encryption: {
                type: "tls"
              }
              login: $address
              auth: {
                type: "password"
                raw: $password
              }
            }
          }
        }
      }
    }
  }
  let config_path = [$tmp "config.toml"] | path join
  $config | to toml | save -f $config_path

  try {
    himalaya --config $config_path ...($args)
  } catch { |e|
    print -e $e.msg
    rm -rf $tmp
    exit 1
  }

  rm -rf $tmp
  exit 0
}
