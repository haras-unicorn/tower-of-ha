def "toh secrets hosts" [] {
  $in | each { |host|
    if ($env.TOH_SECRETS_HOSTS? | is-empty) {
      let key = $"kv/toh/host/($host.name)/current"
      let secrets = vault kv get -format=json $key
        | from json
        | get data.data
      $host | insert secrets $secrets
    } else {
      let secrets = ls ([ $env.TOH_SECRETS_HOSTS $in.name ] | path join)
        | each { { key: (basename $in.name), value: (open --raw $in.name) } }
        | transpose -dr
      $host | insert secrets $secrets
    }
  }
}

def "toh secrets cluster" [] {
  if ($env.TOH_SECRETS_CLUSTER? | is-empty) {
    vault kv get -format=json $env.TOH_VAULT_CLUSTER
      | from json
      | get data.data
  } else {
    ls $env.TOH_SECRETS_CLUSTER
      | each { { key: (basename $in.name), value: (open --raw $in.name) } }
      | transpose -dr
  }
}
