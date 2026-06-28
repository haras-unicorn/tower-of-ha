let base_url = r#'{{{TOH_FORGEJO_OAUTH_BASE_URL}}}'#
let client_secret = r#'{{{TOH_FORGEJO_OAUTH_CLIENT_SECRET}}}'#
let config = r#'{{{TOH_FORGEJO_CONFIG}}}'#
let db = r#'{{{TOH_FORGEJO_DB_INSTANCE}}}'# | from json
let runners = r#'{{{TOH_FORGEJO_RUNNERS}}}'# | from json

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

  for runner in $runners {
    let id = try {
      forgejo register runner $runner.name (open --raw $runner.secret)
    } catch { |e|
      forgejo handle error $e
      exit 1
    }

    try {
      forgejo record runner $runner.name $id
    } catch { |e|
      forgejo handle error $e
      exit 1
    }
  }

  def "forgejo record runner" [name: string id: string] {
    print $"Recording runner ($name)..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          usql (open --raw $db.url) -c $"
            INSERT INTO __toh_action_runners \(name, id\)
            VALUES \('($name)', '($id)'\)
            ON CONFLICT \(name\)
            DO UPDATE SET id = '($id)'
          "
      ) | complete

      if $output.exit_code == 0 {
        print $"Runner ($name) recorded successfully"
        return
      }

      if $attempt == $max_attempts {
        forgejo make error {
          msg: (
            $"Failed to record runner ($name) after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Runner ($name) record attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "forgejo register runner" [name: string secret: path] {
    print $"Registering runner ($name)..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          forgejo forgejo-cli actions register
            --config $config
            --name $name
            --secret (open --raw $secret)
            --scope all
      ) | complete

      if $output.exit_code == 0 {
        print $"Runner ($name) registered successfully"
        return $output.stdout | str trim
      }

      if $attempt == $max_attempts {
        forgejo make error {
          msg: (
            $"Failed to register runner ($name) after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Runner ($name) registration attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "forgejo add oauth" [] {
    print "Adding oauth provider..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          forgejo admin auth add-oauth
            --config $config
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
        return
      }

      if ($output.stderr | str contains "login source already exists") {
        print "OAuth provider already added, nothing to do"
        return
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
            --config $config
      ) | complete

      if $output.exit_code == 0 {
        print $"Auth providers listed successfully:\n($output.stdout)"
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
