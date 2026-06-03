let users_to_envs = r#'{{{TOH_PATRONI_USERS_TO_ENV_PATHS}}}'# | from json
let superusers = r#'{{{TOH_PATRONI_SUPERUSERS}}}'# | from json

def --wrapped "main psql" [user: string, ...args: string] {
  let user_env = $users_to_envs | get $user
  let is_superuser = $superusers | any { $in == $user }

  let tmp = (mktemp -d)
  chmod 700 $tmp

  if ($user_env | path exists) {
    if ($env.USER != root and ($env.USER != $user or $is_superuser)) {
      sudo cat $user_env | from toml | load-env
    } else {
      open --raw $user_env | from toml | load-env
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

    mut psql_env = {
      PGUSER: $user
      PGPASSWORD: $pass
      PGHOST: $proxy.host
      PGPORT: $proxy.port
      PGSSLMODE: "verify-full"
      PGSSLROOTCERT: $ca_path
      PGSSLCERT: $public_path
      PGSSLKEY: $private_path
    }
    if not $is_superuser {
      $psql_env = $psql_env | insert PGDATABASE $user
    }
    $psql_env | load-env
  }

  try {
    psql ...($args)
  } catch { |e|
    print -e $e.msg
    rm -rf $tmp
    exit 1
  }
  rm -rf $tmp
  exit 0
}
