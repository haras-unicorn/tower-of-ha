def --wrapped "main cockroachdb root" [...args: string] {
  let tmp = (mktemp -d)
  chmod 700 $tmp

  if ("{{{TOH_COCKROACHDB_ROOT_ENV_PATH}}}" | path exists) {
    # NOTE: env files are technically a subset of toml
    if ($env.USER != "root") {
      sudo cat "{{{TOH_COCKROACHDB_ROOT_ENV_PATH}}}" | from toml | load-env
    } else {
      open --raw "{{{TOH_COCKROACHDB_ROOT_ENV_PATH}}}" | from toml | load-env
    }
  } else {
    let cluster = toh secrets cluster
    let ca_path = [$tmp "ca.crt"] | path join
    let private_path = [$tmp "client.root.key"] | path join
    let public_path = [$tmp "client.root.crt"] | path join
    touch $ca_path
    touch $private_path
    touch $public_path
    chmod 600 $ca_path
    chmod 600 $private_path
    chmod 600 $public_path
    $cluster.cockroach-ca-public | save -a $ca_path
    $cluster.cockroach-root-private | save -a $private_path
    $cluster.cockroach-root-public | save -a $public_path

    let db_machines = toh cluster machinea | where { $in.database? != null }
    let cockroach_machine = if $db_machines == [ ] {
      printf -e "No cockroachdb machines detected"
      ""
    } else {
      let first = $db_machines | first
      $"($first.database.machine):($first.database.port)"
    }
    let postgres_machine = $db_machines | each { $"($in.database.machine):($in.database.port)" } | str join ","
    let pass = $cluster | get "cockroach-root-pass"

    let url = ($"postgresql://"
      + $"root:($pass)"
      + $"@($cockroach_machine)"
      + "?sslmode=verify-full"
      + $"&sslrootcert=($ca_path)"
      + $"&sslcert=($public_path)"
      + $"&sslkey=($private_path)")

    {
      COCKROACH_URL: $url
      PGUSER: "root"
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
