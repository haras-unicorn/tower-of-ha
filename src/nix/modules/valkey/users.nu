let users = r#'{{{TOH_VALKEY_USERS}}}'# | from json

# Connect to valkey as a registered user
def --wrapped "main valkey" [
  user: string,
  ...args: string
]: nothing -> nothing {
  let config = $users | get $user
  let machine = toh machine current

  let tmp = (mktemp -d)
  chmod 700 $tmp

  mut user_args = []
  if $config.installSecrets {
    $user_args = [
      "--tls"
      "--cacert" $config.ca
      "--cert" $config.crt
      "--key" $config.key
      "--user" $user
      "--pass" (open --raw $config.password)
      "--no-auth-warning"
    ]
  } else {
    let cluster = toh secrets cluster
    let ca_path = [$tmp "ca.crt"] | path join
    let private_path = [$tmp $"user.key"] | path join
    let public_path = [$tmp $"user.crt"] | path join
    let password = $cluster | get $"valkey-($user)-pass"
    touch $ca_path
    touch $private_path
    touch $public_path
    chmod 600 $ca_path
    chmod 600 $private_path
    chmod 600 $public_path
    $cluster.valkey-ca-public | save -a $ca_path
    $cluster | get $"valkey-($user)-private" | save -a $private_path
    $cluster | get $"valkey-($user)-public" | save -a $public_path
    $user_args = [
      "--tls"
      "--cacert" $ca_path
      "--cert" $public_path
      "--key" $private_path
      "--user" $user
      "--pass" $password
      "--no-auth-warning"
    ]
  }

  try {
    (valkey-cli
      -h $machine.meta.proxies.valkey.endpoint.redis.host
      -p $machine.meta.proxies.valkey.endpoint.redis.port
      ...($user_args)
      ...($args))
  } catch { |e|
    print -e $"Failed to connect: ($e.msg)"
    rm -rf $tmp
    exit 1
  }

  rm -rf $tmp
}
