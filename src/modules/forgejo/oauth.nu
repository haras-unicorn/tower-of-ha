let base_url = r#'{{{TOH_OPENBAO_OAUTH_BASE_URL}}}'#
let client_secret = r#'{{{TOH_OPENBAO_OAUTH_CLIENT_SECRET}}}'#

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --timeout: int = 30,
] {
  let providers = try {
    forgejo list auth
  } catch { |e|
    forgejo handle error $e
    exit 1
  }

  if ($providers | str contains "forgejo") {
    exit 0
  }

  try {
    forgejo add oauth
  } catch { |e|
    forgejo handle error $e
    exit 1
  }

  def "forgejo add oauth" [] {
    print "Adding oauth provider..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          forgejo admin auth add-oauth
            $"--auto-discover-url=($base_url)/.well-known/openid-configuration"
            --name=forgejo
            --provider=openidConnect
            --key=forgejo
            $"--secret=(open --raw $client_secret)"
            --scopes='openid email profile groups forgejo'
            --attribute-ssh-public-key=sshpubkey
      ) | complete

      if $output.exit_code == 0 {
        print "OAuth provider added successfully"
        return $output.stdout
      }

      if $attempt == $max_attempts {
        forgejo make error {
          msg: (
            $"Failed to add OAuth provider after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"OAuth provider addition attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "forgejo list auth" [] {
    print "Listing auth providers..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          forgejo admin auth list
      ) | complete

      if $output.exit_code == 0 {
        print "Auth providers listed successfully"
        return $output.stdout
      }

      if $attempt == $max_attempts {
        forgejo make error {
          msg: (
            $"Failed to list auth providers after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Auth provider listing attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "forgejo make error" [msg] {
    error make {
      msg: ($msg | to json)
    }
  }

  def "forgejo handle error" [e] {
    let data = $e.msg | from json
    if ($data | describe) == "string" {
      print -e $e.msg
    } else {
      print -e $data.msg
    }
    exit 1
  }
}
