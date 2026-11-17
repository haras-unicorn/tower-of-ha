let users = r#'{{{TOH_S3_USERS}}}'# | from json

# Connect to S3 as a registered user
def --wrapped "main s3" [
  user: string,
  ...args: string
]: nothing -> nothing {
  let config = $users | get $user

  let machine = toh machine current
  let host = $machine.meta.proxies.garage.endpoint.s3.host
  let port = $machine.meta.proxies.garage.endpoint.s3.port

  let access_key = if $config.installSecrets {
    (open --raw $config.keyId)
  } else {
    (toh secrets cluster) | get $"garage-key-($user)-id"
  }

  let secret_key = if $config.installSecrets {
    (open --raw $config.secretKey)
  } else {
    (toh secrets cluster) | get $"garage-key-($user)-secret"
  }

  try {
    (s3cmd
      "--ssl"
      $"--host=($host):($port)"
      $"--host-bucket=($host):($port)"
      $"--access_key=($access_key)"
      $"--secret_key=($secret_key)"
      ...($args))
  } catch { |e|
    print -e $"Failed to connect: ($e.msg)"
    exit 1
  }
}
