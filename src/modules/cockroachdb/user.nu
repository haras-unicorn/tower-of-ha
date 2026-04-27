def --wrapped "main cockroachdb user" [...args: string] {
  let tmp = (mktemp -d)
  chmod 700 $tmp

  let machine = toh machine current
  if ("{{{TOH_COCKROACHDB_USER_ENV_PATH}}}" | path exists) {
    # NOTE: replace home so when running as another user the location is correct
    let env_path = "{{{TOH_COCKROACHDB_USER_ENV_PATH}}}"
    # NOTE: env files are technically a subset of toml
    if ($env.USER != $machine.meta.user.user) {
      sudo cat $env_path | from toml | load-env
    } else {
      open --raw $env_path | from toml | load-env
    }
  } else {
    let cluster = toh secrets cluster
    let ca_path = [$tmp "ca.crt"] | path join
    let private_path = [$tmp "client.user.key"] | path join
    let public_path = [$tmp "client.user.crt"] | path join
    touch $ca_path
    touch $private_path
    touch $public_path
    chmod 600 $ca_path
    chmod 600 $private_path
    chmod 600 $public_path
    $cluster.cockroach-ca-public | save -a $ca_path
    $cluster | get $"cockroach-($machine.meta.user.user)-private" | save -a $private_path
    $cluster | get $"cockroach-($machine.meta.user.user)-public" | save -a $public_path

    let db_machines = toh cluster machinea | where { $in.database? != null }
    let db_user = if $db_machines == [ ] {
      printf -e "No cockroachdb machines detected"
      ""
    } else {
      $db_machines | get 0.user
    }
    let cockroach_machine = if $db_machines == [ ] {
      printf -e "No cockroachdb machines detected"
      ""
    } else {
      let first = $db_machines | first
      $"($first.database.machine):($first.database.port)"
    }
    let postgres_machine = $db_machines | each { $"($in.database.machine):($in.database.port)" } | str join ","
    let pass = $cluster | get $"cockroach-($db_user)-pass"

    let url = ($"postgresql://"
      + $"($db_user):($pass)"
      + $"@($cockroach_machine)"
      + "?sslmode=verify-full"
      + $"&sslusercert=($ca_path)"
      + $"&sslcert=($public_path)"
      + $"&sslkey=($private_path)")

    {
      COCKROACH_URL: $url
      PGUSER: $db_user
      PGPASSWORD: $pass
      PGmachine: $postgres_machine
      PGSSLMODE: "verify-full"
      PGSSLROOTCERT: $ca_path
      PGSSLCERT: $public_path
      PGSSLKEY: $private_path
    } | load-env
  }

  let result = cockroachdb ...($args) | complete
  rm -rf $tmp
  print $result.stdout
  print -e $result.stderr
  exit $result.exit_code
}
