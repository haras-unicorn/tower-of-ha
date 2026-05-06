let env_path = "{{{TOH_VAULTWARDEN_INIT_ENV_PATH}}}"
let data_dir = "{{{TOH_VAULTWARDEN_INIT_DATA_DIR}}}"
let user = "{{{TOH_VAULTWARDEN_INIT_USER}}}"
let exe = "{{{TOH_VAULTWARDEN_INIT_EXE}}}"
let bash = "{{{TOH_VAULTWARDEN_INIT_BASH}}}"

def "main" [] {
  print "Running vaultwarden migrations..."

  mkdir $data_dir
  chown $"($user):($user)" $data_dir
  let log_file = mktemp -t
  mut migrations_done = false
  let vaultwarden_pid = with-env {
    # NOTE: env is technically valid toml
    $env.DATABASE_URL = (cat $env_path | from toml | get DATABASE_URL)
    $env.ADMIN_TOKEN = "temp"
    $env.ROCKET_ADDRESS = "127.0.0.1"
    $env.ROCKET_PORT = "18222"
    $env.SIGNUPS_ALLOWED = "true"
    $env.ENABLE_WEBSOCKET = "false"
    $env.DATA_FOLDER = $data_dir
    $env.WEB_VAULT_ENABLED = "false"
    $env.EXTENDED_LOGGING = "true"
    $env.LOG_LEVEL = "info"
  } {
    nu -c $"($bash) -c '($exe) > ($log_file) 2>&1 & disown %-; echo $!'"
  } | str trim
    | into int

  for line in (tail -n +1 -f $log_file | lines) {
    print $"Vaultwarden: ($line)"
    if ($line | str contains "Rocket has launched") {
      print "Vaultwarden server launched"
      $migrations_done = true
      kill $vaultwarden_pid
      break
    }
  }

  if not $migrations_done {
    print "Vaultwarden failed before migrations completed"
    exit 1
  }

  rm -rf $log_file
  print "Vaultwarden migrations completed successfully"
}
