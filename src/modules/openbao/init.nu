let sops_file = r#'{{{TOH_OPENBAO_SOPS_FILE}}}'#
let machine_acl_template = r#'{{{TOH_OPENBAO_MACHINE_ACL_TEMPLATE_FILE}}}'#
let admin_acl = r#'{{{TOH_OPENBAO_ADMIN_ACL_FILE}}}'#
let address = r#'{{{TOH_OPENBAO_ADDRESS}}}'#
let machine_name = r#'{{{TOH_OPENBAO_MACHINE_NAME}}}'#
let machine_passwords = r#'{{{TOH_OPENBAO_MACHINE_PASSWORDS}}}'# | from json
let admin_password = r#'{{{TOH_OPENBAO_ADMIN_PASSWORD}}}'#
let root_fail_path = r#'{{{TOH_OPENBAO_ROOT_FAIL_PATH}}}'#
let machines_key = r#'{{TOH_OPENBAO_MACHINES_KEY}}'#
let root_key = r#'{{TOH_OPENBAO_ROOT_KEY}}'#
let keys_mount = r#'{{{TOH_OPENBAO_KEYS_MOUNT}}}'#
let age_key_path = r#'{{{TOH_OPENBAO_AGE_KEY_PATH}}}'#

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --timeout: int = 30,
] {
  let root = try {
    openbao initialize
  } catch { |e|
    openbao handle error $e
    if ($root_fail_path | path exists) {
      print $"Reading root from '($root_fail_path)'..."
      open --raw $root_fail_path | from json
    } else {
      exit 1
    }
  }

  if $root != null {
    try {
      openbao enable kv $root.root_token
    } catch { |e|
      openbao handle error $e
      $root | to json | save -f $root_fail_path
      exit 1
    }

    try {
      openbao upload $root.root_token $root_key $root
    } catch { |e|
      openbao handle error $e
      $root | to json | save -f $root_fail_path
      exit 1
    }

    try {
      openbao enable userpass $root.root_token
    } catch { |e|
      openbao handle error $e
      exit 1
    }

    let userpass_accessor = try {
      openbao fetch userpass accessor $root.root_token
    } catch { |e|
      openbao handle error $e
      exit 1
    }

    for policy in [
      {
        name: machine
        value: (
          open --raw $machine_acl_template
            | str replace --all "<USERPASS_ACCESSOR>" $userpass_accessor
        )
      }
      { name: admin value: (open --raw $admin_acl) }
    ] {
      try {
        (openbao create policy
          $root.root_token
          $policy.name
          $policy.value)
      } catch { |e|
        openbao handle error $e
        exit 1
      }
    }

    for user in (
      ($machine_passwords | transpose name password | insert policy machine)
      ++ [{ name: admin password: $admin_password policy: admin }]
    ) {
      try {
        (openbao create user
          $root.root_token
          $user.name
          (open --raw $user.password)
          $user.policy)
      } catch { |e|
        openbao handle error $e
        exit 1
      }
    }

    try {
      openbao revoke token root $root.root_token
    } catch { |e|
      openbao handle error $e
      exit 1
    }

    if ($root_fail_path | path exists) {
      print $"Shredding root from '($root_fail_path)'..."
      shred -zu $root_fail_path
    }
  }

  let secrets = try {
    openbao decrypt sops
  } catch { |e|
    openbao handle error $e
    exit 1
  }

  mut token = ""
  loop {
    try {
      $token = openbao login
      break
    } catch { |e|
      openbao handle error $e
    }
  }

  try {
    (openbao upload
      $token
      $"($machines_key)/($machine_name)"
      $secrets)
  } catch { |e|
    openbao handle error $e
    exit 1
  }

  def "openbao upload" [
    token: string,
    path: string,
    data: record
  ] {
    print $"Uploading ($path) to OpenBao..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        $data
          | to json
          | timeout $"($timeout)s" bao kv put $"-mount=($keys_mount)" $path -
          | complete
      }

      if $output.exit_code == 0 {
        print $"OpenBao ($path) upload completed successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to upload ($path) to OpenBao after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao upload of ($path) attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao decrypt sops" [] {
    print $"Decrypting SOPS file with age key '($age_key_path)'..."
    let output = with-env {
      SOPS_AGE_KEY_FILE: $age_key_path
    } {
      sops decrypt --output-type json $sops_file | complete
    }

    if $output.exit_code == 0 {
      print "SOPS file decrypted successfully"
      return ($output.stdout | from json)
    }

    openbao make error {
      msg: (
        $"Failed to decrypt SOPS file"
        + $":\n($output.stderr)"
      )
    }
  }

  def "openbao create user" [
    token: string,
    name: string,
    password: string,
    policy: string
  ] {
    print $"Writing policy ($name) to OpenBao..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao write $"auth/userpass/users/($name)"
              $"password=($password)"
              $"policies=($policy)"
        ) | complete
      }

      if $output.exit_code == 0 {
        print $"OpenBao ($name) user created successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to create ($name) OpenBao user after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao ($name) user creation attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao create policy" [
    token: string,
    name: string,
    policy: string
  ] {
    print $"Creating policy ($name) to OpenBao..."
    print $policy
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        $policy
          | timeout $"($timeout)s" bao policy write $name -
          | complete
      }

      if $output.exit_code == 0 {
        print $"OpenBao ($name) policy created successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to create ($name) OpenBao policy after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao ($name) policy creation attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao revoke token" [name: string, token: string] {
    print $"Revoking OpenBao ($name) token..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao token revoke $token
        ) | complete
      }

      if $output.exit_code == 0 {
        print $"OpenBao ($name) token revoked successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to revoke ($name) OpenBao token after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao ($name) token revoke attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao fetch userpass accessor" [token: string] {
    print "Fetching OpenBao userpass accessor..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao read -field=accessor sys/mounts/auth/userpass
        ) | complete
      }

      if $output.exit_code == 0 {
        print "OpenBao userpass accessor fetched successfully"
        return ($output.stdout | str trim)
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to fetch OpenBao userpass accessor after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao userpass accessor fetch attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao enable userpass" [token: string] {
    print "Enabling userpass auth in OpenBao..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao auth enable userpass
        ) | complete
      }

      if $output.exit_code == 0 {
        print "OpenBao userpass enabled successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to enable OpenBao userpass after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao userpass enable attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao enable kv" [token: string] {
    print "Enabling kv store in OpenBao..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao secrets enable
              $"-path=($keys_mount)"
              kv-v2
        ) | complete
      }

      if $output.exit_code == 0 {
        print "OpenBao kv enabled successfully"
        return
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to enable OpenBao kv after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao kv enable attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao login" [] {
    print "Logging into OpenBao..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: null
      } {
        (
          timeout $"($timeout)s"
            bao login
              -token-only
              -method=userpass
              $"username=($machine_name)"
              $"password=(open --raw ($machine_passwords | get $machine_name))"
        ) | complete
      }

      if $output.exit_code == 0 {
        print "Logged into OpenBao successfully"
        return $output.stdout | str trim
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to log into OpenBao after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao login attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao initialize" [] {
    print "Initializing OpenBao..."
    for attempt in 1..$max_attempts {
      # NOTE: HOME because it tries to spawn the token helper
      # without it for some reason
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: null
        HOME: "/root"
      } {
        (
          timeout $"($timeout)s"
            bao operator init -format=json
        ) | complete
      }

      if $output.exit_code == 0 {
        print "Initialized OpenBao successfully"
        return ($output.stdout | from json)
      }

      if ($output.stderr | str contains "Vault is already initialized") {
        print "OpenBao already initialized"
        return null
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to initialize OpenBao after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao initialization at '($address)' attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "openbao make error" [msg] {
    error make {
      msg: ($msg | to json)
    }
  }

  def "openbao handle error" [e] {
    let data = $e.msg | from json
    if ($data | describe) == "string" {
      print -e $e.msg
    } else {
      print -e $data.msg
    }
    exit 1
  }
}
