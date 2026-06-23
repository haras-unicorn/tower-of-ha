let token_path = r#'{{{TOH_OPENBAO_TOKEN_PATH}}}'#
let response_path = r#'{{{TOH_OPENBAO_RESPONSE_PATH}}}'#
let address = r#'{{{TOH_OPENBAO_ADDRESS}}}'#
let machine_username = r#'{{{TOH_OPENBAO_MACHINE_USERNAME}}}'#
let machine_password_path = r#'{{{TOH_OPENBAO_MACHINE_PASSWORD_PATH}}}'#

def "main" [
  hours: int,
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --timeout: int = 30,
] {
  let login_token = try {
    openbao login
  } catch { |e|
    openbao handle error $e
    exit 1
  }

  let token = try {
    openbao create token $login_token
  } catch { |e|
    openbao handle error $e
    exit 1
  }

  try {
    $token | openbao save token
  } catch { |e|
    openbao handle error $e
    exit 1
  }

  def "openbao create token" [token: string] {
    print "Creating OpenBao token..."
    for attempt in 1..$max_attempts {
      let output = with-env {
        BAO_ADDR: $address
        BAO_TOKEN: $token
      } {
        (
          timeout $"($timeout)s"
            bao token create
              -format=json
              $"-ttl=($hours)h"
        ) | complete
      }

      if $output.exit_code == 0 {
        print "OpenBao token created successfully"
        return ($output.stdout | from json | get auth.client_token)
      }

      if $attempt == $max_attempts {
        openbao make error {
          msg: (
            $"Failed to create OpenBao token after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OpenBao token creation attempt ($attempt) failed"
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
              $"username=($machine_username)"
              $"password=(open --raw $machine_password_path)"
        ) | complete
      }

      if $output.exit_code == 0 {
        print "Logged into OpenBao successfully"
        return ($output.stdout | str trim)
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

  def "openbao save token" [] {
    $in | save -f $response_path
    mv $response_path $token_path
    chmod 400 $token_path
    chown root:root $token_path
    print "OpenBao token saved"
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
