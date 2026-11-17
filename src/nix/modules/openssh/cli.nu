def --wrapped "main ssh shell" [--machine: string, ...args: string] {
  let args = $args | each { $"'($in)'" } | str join " "

  let machine = toh machine pick --with-secrets $machine

  ssh-agent bash -c $"echo '($machine.secrets."ssh-private")' \\
    | ssh-add - \\
    && ssh -t ($args) ($machine.meta.user.user)@($machine.meta.network.ip) motd-wrap nu"
}

def --wrapped "main ssh command" [--machine: string, command: string, ...args: string] {
  let args = $args | each { $"'($in)'" } | str join " "

  let machine = toh machine pick --with-secrets $machine

  ssh-agent bash -c $"echo '($machine.secrets."ssh-private")' \\
    | ssh-add - \\
    && ssh ($machine.meta.user.user)@($machine.meta.network.ip) '($command)' ($args)"
}

def --wrapped "main ssh copy" [from: string, to: string, ...args: string] {
  let args = $args | each { $"'($in)'" } | str join " "

  let from_split = $from | split row -n 2 ":"
  let to_split = $to | split row -n 2 ":"

  let from_machine = if ($from_split | length) == 2 {
    toh machine pick --with-secrets $from_split.0
  } else {
    null
  }
  let to_machine = if ($to_split | length) == 2 {
    toh machine pick --with-secrets $to_split.0
  } else {
    null
  }

  let keys = ""
  let keys = if $from_machine != null {
    $"($keys) echo '($from_machine.secrets."ssh-private")' | ssh-add - &&"
  } else {
    $keys
  }
  let keys = if $to_machine != null {
    $"($keys) echo '($to_machine.secrets."ssh-private")' | ssh-add - &&"
  } else {
    $keys
  }

  let source = if $from_machine != null {
    $"($from_machine.meta.user.user)@($from_machine.meta.network.ip):($from_split.1)"
  } else {
    $from
  }
  let destination = if $to_machine != null {
    $"($from_machine.meta.user.user)@($to_machine.meta.network.ip):($to_split.1)"
  } else {
    $to
  }

  ssh-agent bash -c $"($keys) scp ($args) ($source) ($destination)"
}
