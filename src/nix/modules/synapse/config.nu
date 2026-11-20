def main [] {
  let settings = r#'{{{TOH_SYNAPSE_CONFIG}}}'# | from json

  install-file $settings.path $settings.owner $settings.group
  {
    database: {
      name: $settings.database.name
      args: ($settings.database.args | insert password (read-secret $settings.passwordPath))
    }
    registration_shared_secret: (read-secret $settings.registrationSecretPath)
    macaroon_secret_key: (read-secret $settings.macaroonSecretPath)
    worker_replication_secret: (read-secret $settings.replicationSecretPath)
  } | to yaml | save --force $settings.path

  # NOTE: the signing key has to be the same on every machine, because the
  # main process moves between them, so it is made from a secret of the
  # cluster and not by Synapse
  let seed = read-secret $settings.signingSeedPath | hash sha256 --binary | encode base64 --nopad
  install-file $settings.signingKeyPath $settings.owner $settings.group
  $"ed25519 ($settings.signingKeyVersion) ($seed)\n" | save --force $settings.signingKeyPath
}

def read-secret [path: string] {
  open --raw $path | str trim
}

def install-file [path: string, owner: string, group: string] {
  ^install --mode 0400 --owner $owner --group $group /dev/null $path
}
