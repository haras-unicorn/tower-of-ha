let cluster = r#'{{{TOH_CLUSTER}}}'# | from json

def "main machine pass" [machine?: string] {
 toh machine pick --with-secrets $machine | get secrets."pass-priv"
}

def "toh machine current" [--with-secrets] {
  if $with_secrets {
    toh machine pick (hostname) --with-secrets
  } else {
    toh machine pick (hostname)
  }
}

def "toh machine pick" [--with-secrets, name?: string] {
  let name = if $name == null {
    gum choose --header "Pick machine name:" ...(toh cluster machinea | get name )
  } else {
    $name
  }

  let machine = toh cluster machines | get $name
  if not $with_secrets {
    $machine
  }

  $machine | insert secrets (toh secrets machine $machine.name)
}

def "toh cluster machinea" [--with-secrets] {
  if $with_secrets {
    toh cluster --with-secrets
  } else {
    toh cluster
  } | get machinea
}

def "toh cluster machines" [--with-secrets] {
  if $with_secrets {
    toh cluster --with-secrets
  } else {
    toh cluster
  } | get machines
}

def "toh cluster" [--with-secrets] {
  if not $with_secrets {
    return $cluster
  }

  let secrets = toh secrets machines
  let machinea = $cluster.machinea
    | insert secrets { ($secrets | get -o $in.name) }

  $cluster
    | update machinea $machinea
    | update machines {
        $machinea
          | each {
              {
                key: $in.name
                value: $in
              }
            }
          | transpose -idr
      }
}
