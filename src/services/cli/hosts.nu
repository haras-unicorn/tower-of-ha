def "main host pass" [host?: string] {
 toh host pick --with-secrets $host | get secrets."pass-priv"
}

def "toh host current" [--with-secrets] {
  let hosts = toh host all
  let host = $hosts | where name == (hostname) | first

  if not $with_secrets {
    return $host
  }

  [ $host ] | toh secrets hosts | first
}

def "toh host first" [--with-secrets, filter?: closure] {
  let hosts = toh host all
  let host = if $filter != null {
    $hosts | where $filter | first
  } else {
    $hosts | first
  }

  if not $with_secrets {
    return $host
  }

  [ $host ] | toh secrets hosts | first
}

def "toh host filter" [--with-secrets, filter?: closure] {
  let hosts = toh host all
  let filtered = if $filter != null {
    $hosts | where $filter
  } else {
    $hosts
  }

  if not $with_secrets {
    return $filtered
  }

  $filtered | toh secrets hosts
}

def "toh host pick" [--with-secrets, name?: string] {
  let hosts = toh host all
  mut host = null

  if ($name != null) {
    $host = $hosts | where $it.name == $name | first
  } else {
    let wanted = (gum choose --header "Pick host name:" ...($hosts | get name ))
    $host = $hosts | where $it.name == $wanted | first
  }

  if not $with_secrets {
    return $host
  }

  [ $host ] | toh secrets hosts | first
}

def "toh host all" [--with-secrets] {
  mut hosts = $env.TOH_HOSTS
    | from json

  $hosts = $hosts | each { |host|
    $host | insert configuration $host.name
  }

  if not $with_secrets {
    return $hosts
  }

  $hosts | toh secrets hosts
}
