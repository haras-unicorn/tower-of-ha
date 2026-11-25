let name = r#'{{{TOH_VALKEY_PRIMARY_NAME}}}'#
let own_ip = r#'{{{TOH_VALKEY_PRIMARY_OWN_IP}}}'#
let bootstrap_ip = r#'{{{TOH_VALKEY_PRIMARY_BOOTSTRAP_IP}}}'#
let port = r#'{{{TOH_VALKEY_PRIMARY_PORT}}}'#
let sentinel_port = r#'{{{TOH_VALKEY_PRIMARY_SENTINEL_PORT}}}'#
let sentinels = r#'{{{TOH_VALKEY_PRIMARY_SENTINELS}}}'# | from json
let user = r#'{{{TOH_VALKEY_PRIMARY_USER}}}'#
let password_file = r#'{{{TOH_VALKEY_PRIMARY_PASSWORD}}}'#
let ca = r#'{{{TOH_VALKEY_PRIMARY_CA}}}'#
let server_conf = r#'{{{TOH_VALKEY_PRIMARY_SERVER_CONF}}}'#
let sentinel_conf = r#'{{{TOH_VALKEY_PRIMARY_SENTINEL_CONF}}}'#
let bootstrapped = r#'{{{TOH_VALKEY_PRIMARY_BOOTSTRAPPED}}}'#
let timeout = r#'{{{TOH_VALKEY_PRIMARY_TIMEOUT}}}'#

# NOTE: Nushell runs the subcommands of main only when main itself exists
def main [] {
  error make { msg: "run it as valkey-primary server or valkey-primary sentinel" }
}

# Points the server at the primary before it starts: the one the other
# sentinels agree on last, else what the server kept from before, and only on
# its very first start the bootstrap primary
def "main server" [] {
  let primary = primary of sentinels
  if $primary == null and ($bootstrapped | path exists) {
    print "no sentinel answered, so the server keeps the role it had"
    return
  }

  let primary = $primary | default { ip: $bootstrap_ip, port: $port }
  let kept = open --raw $server_conf
    | lines
    | where { |line| $line !~ '^(replicaof|slaveof) ' }
  let replication = if $primary.ip == $own_ip {
    print "the server starts as the primary"
    []
  } else {
    print $"the server starts as a replica of ($primary.ip)"
    [$"replicaof ($primary.ip) ($primary.port)"]
  }
  $kept | append $replication | str join "\n" | $in + "\n" | save --force $server_conf
  touch $bootstrapped
}

# Points the sentinel at the primary before it starts: the one the other
# sentinels agree on last, else the one the server of this machine follows
def "main sentinel" [] {
  let agreed = primary of sentinels
  let primary = if $agreed == null { primary of server } else { $agreed }
  print $"the sentinel monitors ($primary.ip)"
  let monitor = $'^sentinel monitor ($name) \S+ \S+ '
  # NOTE: the replicas the sentinel kept may name the new primary, which it
  # would then turn into a replica of itself; it finds them again from the
  # primary within seconds
  let replica = $'^sentinel known-replica ($name) '
  open --raw $sentinel_conf
    | lines
    | where { |line| $line !~ $replica }
    | each { |line|
      $line | str replace --regex $monitor $"sentinel monitor ($name) ($primary.ip) ($primary.port) "
    }
    | str join "\n"
    | $in + "\n"
    | save --force $sentinel_conf
}

# NOTE: the sentinel with the highest config epoch saw the last failover
def "primary of sentinels" [] {
  let answers = $sentinels | each { |sentinel|
    try {
      let master = ask $sentinel $sentinel_port SENTINEL master $name
        | chunks 2
        | reduce --fold {} { |pair, record| $record | upsert $pair.0 $pair.1 }
      { ip: $master.ip, port: $master.port, epoch: ($master | get "config-epoch" | into int) }
    } catch {
      null
    }
  } | compact

  if ($answers | is-empty) {
    null
  } else {
    $answers | sort-by epoch | last | reject epoch
  }
}

def "primary of server" [] {
  let replication = ask $own_ip $port INFO replication
    | parse "{key}:{value}"
    | transpose --header-row --as-record
  if $replication.role == "master" {
    { ip: $own_ip, port: $port }
  } else {
    { ip: $replication.master_host, port: $replication.master_port }
  }
}

def ask [host: string, port: string, ...command: string] {
  let password = open --raw $password_file | str trim
  with-env { VALKEYCLI_AUTH: $password, REDISCLI_AUTH: $password } {
    (^timeout $timeout valkey-cli -e --no-auth-warning --tls --cacert $ca
      -h $host -p $port --user $user ...$command)
  } | lines | each { |line| $line | str trim }
}
