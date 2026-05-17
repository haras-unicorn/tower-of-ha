let users_to_envs = r#'{{{TOH_PATRONI_USERS_TO_ENV_PATHS}}}'# | from json

def --wrapped "main psql" [user: string, ...args: string] {
  let userEnv = $users_to_envs | get $user
  let tmp = (mktemp -d)
  chmod 700 $tmp

  if ($userEnv | path exists) {
    if ($env.USER != $user or $user == "postgresql") and $env.USER != root {
      sudo cat $userEnv | from toml | load-env
    } else {
      open --raw $userEnv | from toml | load-env
    }
  } else {
    let cluster = toh secrets cluster
    let ca_path = [$tmp "ca.crt"] | path join
    let private_path = [$tmp $"user.key"] | path join
    let public_path = [$tmp $"user.crt"] | path join
    touch $ca_path
    touch $private_path
    touch $public_path
    chmod 600 $ca_path
    chmod 600 $private_path
    chmod 600 $public_path
    $cluster.patroni-ca-public | save -a $ca_path
    $cluster | get $"patroni-($user)-private" | save -a $private_path
    $cluster | get $"patroni-($user)-public" | save -a $public_path

    let machine = toh machine current
    let proxy = $machine.proxies.postgresql
    let pass = $cluster | get $"patroni-($user)-pass"

    {
      PGUSER: $user
      PGPASSWORD: $pass
      PGHOST: $proxy.host
      PGPORT: $proxy.port
      PGSSLMODE: "verify-full"
      PGSSLROOTCERT: $ca_path
      PGSSLCERT: $public_path
      PGSSLKEY: $private_path
    } | load-env
  }

  let result = psql ...($args) | complete
  rm -rf $tmp
  print $result.stdout
  print -e $result.stderr
  exit $result.exit_code
}
