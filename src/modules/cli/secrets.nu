let secrets = "{{{TOH_LIB_SECRETS}}}" | from json

def "toh secrets machines" [] {
  if ($secrets.directories.machines | path exists) {
    ls $secrets.directories.machines
      | each {
          {
            key: (basename $in.name),
            value: (
              ls $in.name
                | each {
                    {
                      key: (basename $in.name)
                      value: (open --raw $in.name)
                    }
                  }
                | transpose -idr
            )
          }
        }
      | transpose -idr
  } else {
    vault kv get -format=json $secrets.keys.machines
      | from json
      | get data.data
  }
}

def "toh secrets machine" [name: string] {
  if ($secrets.directories.machines | path exists) {
    ls ([ $secrets.directories.machines $name ] | path join)
      | each {
          {
            key: (basename $in.name),
            value: (open --raw $in.name)
          }
        }
      | transpose -idr
  } else {
    vault kv get -format=json $"($secrets.keys.machines)/($name)"
      | from json
      | get data.data
  }
}

def "toh secrets cluster" [] {
  if ($secrets.directories.cluster | path exists) {
    ls $secrets.directories.cluster
      | each { { key: (basename $in.name), value: (open --raw $in.name) } }
      | transpose -dr
  } else {
    vault kv get -format=json $secrets.keys.cluster
      | from json
      | get data.data
  }
}

def "toh secrets external" [] {
  if ($secrets.directories.external | path exists) {
    ls $secrets.directories.external
      | each { { key: (basename $in.name), value: (open --raw $in.name) } }
      | transpose -dr
  } else {
    vault kv get -format=json $secrets.keys.external
      | from json
      | get data.data
  }
}
