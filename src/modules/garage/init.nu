let keys = "{{{TOH_GARAGE_INIT_KEYS}}}" | from json
let buckets = "{{{TOH_GARAGE_INIT_BUCKETS}}}" | from json
let layout_version = "{{{TOH_GARAGE_INIT_LAYOUT_VERSION}}}"
let capacity = "{{{TOH_GARAGE_INIT_CAPACITY}}}"

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --init-timeout: int = 30,
  --script-timeout: int = 600
] {
  try {
    garage initialize layout
  } catch { |e|
    garage handle error $e
  }

  try {
    garage wait healthy
  } catch { |e|
    garage handle error $e
  }

  try {
    garage initialize keys
  } catch { |e|
    garage handle error $e
  }

  try {
    garage initialize buckets
  } catch { |e|
    garage handle error $e
  }

  print "Garage initialization complete"

  def "garage wait healthy" [] {
    print "Waiting for garage to be healthy..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($init_timeout)s"
          garage status
      ) | complete

      if $output.exit_code == 0 and ($output.stdout | str downcase | str contains "healthy") {
        print "Garage is healthy"
        break
      }

      if $attempt == $max_attempts {
        garage make error {
          msg: (
            $"Failed to wait for garage healthy after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Garage health check attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "garage initialize layout" [] {
    print "Initializing garage layout..."
    for attempt in 1..$max_attempts {
      let node_output = (
        timeout $"($init_timeout)s"
          garage node id
      ) | complete

      if $node_output.exit_code != 0 {
        if $attempt == $max_attempts {
          garage make error {
            msg: (
              $"Failed to get node ID after ($max_attempts) attempts"
              + $":\n($node_output.stderr)"
            )
          }
        }
        print (
          $"Getting node ID attempt ($attempt) failed"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
        continue
      }

      let node_id = ($node_output.stdout | str trim | lines | first | split row '@' | first)

      let layout_output = (
        timeout $"($init_timeout)s"
          garage layout show
      ) | complete

      if $layout_output.exit_code != 0 {
        if $attempt == $max_attempts {
          garage make error {
            msg: (
              $"Failed to show layout after ($max_attempts) attempts"
              + $":\n($layout_output.stderr)"
            )
          }
        }
        print (
          $"Layout show attempt ($attempt) failed"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
        continue
      }

      if ($layout_output.stdout | str contains $node_id) {
        print "Node already in layout"
      } else {
        print $"Assigning node ($node_id) to layout"
        let assign_output = (
          timeout $"($init_timeout)s"
            garage layout assign -z dc1 -c $capacity $node_id
        ) | complete

        if $assign_output.exit_code != 0 {
          if $attempt == $max_attempts {
            garage make error {
              msg: (
                $"Failed to assign node after ($max_attempts) attempts"
                + $":\n($assign_output.stderr)"
              )
            }
          }
          print (
            $"Layout assign attempt ($attempt) failed"
            + $", retrying in ($retry_delay) seconds..."
          )
          sleep ($retry_delay | into duration --unit sec)
          continue
        }
      }

      print $"Applying layout version ($layout_version)"
      let apply_output = (
        timeout $"($init_timeout)s"
          garage layout apply --version $layout_version
      ) | complete

      if $apply_output.exit_code == 0 or ($apply_output.stderr | str contains "already exists") or ($apply_output.stderr | str contains "Invalid new layout version") {
        print "Layout applied successfully"
        break
      }

      if $attempt == $max_attempts {
        garage make error {
          msg: (
            $"Failed to apply layout after ($max_attempts) attempts"
            + $":\n($apply_output.stderr)"
          )
        }
      }

      print (
        $"Layout apply attempt ($attempt) failed"
        + $" with stdout '($apply_output.stdout)'"
        + $" and stderr '($apply_output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "garage initialize keys" [] {
    if ($keys | length) == 0 {
      print "No keys to import"
      return
    }

    for key in $keys {
      print $"Importing key: ($key.keyId)"
      for attempt in 1..$max_attempts {
        let check = (
          timeout $"($init_timeout)s"
            garage key info (open $key.keyId | str trim)
        ) | complete

        if $check.exit_code == 0 {
          print $"Key ($key.keyId) already exists"
          break
        }

        let output = (
          timeout $"($init_timeout)s"
            garage key import
              (open $key.keyId | str trim)
              (open $key.secretKey | str trim)
              --yes
        ) | complete

        if $output.exit_code == 0 {
          print $"Key ($key.keyId) imported successfully"
          break
        }

        if $attempt == $max_attempts {
          garage make error {
            msg: (
              $"Failed to import key ($key.keyId) after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          }
        }

        print (
          $"Key import ($key.keyId) attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }

    print "All keys imported"
  }

  def "garage initialize buckets" [] {
    if ($buckets | length) == 0 {
      print "No buckets to create"
      return
    }

    for entry in $buckets {
      print $"Creating bucket: ($entry.bucket)"
      for attempt in 1..$max_attempts {
        let check = (
          timeout $"($init_timeout)s"
            garage bucket info $entry.bucket
        ) | complete

        if $check.exit_code != 0 {
          let output = (
            timeout $"($init_timeout)s"
              garage bucket create $entry.bucket
          ) | complete

          if $output.exit_code != 0 {
            if $attempt == $max_attempts {
              garage make error {
                msg: (
                  $"Failed to create bucket ($entry.bucket) after ($max_attempts) attempts"
                  + $":\n($output.stderr)"
                )
              }
            }

            print (
              $"Bucket create ($entry.bucket) attempt ($attempt) failed"
              + $" with stdout '($output.stdout)'"
              + $" and stderr '($output.stderr)'"
              + $", retrying in ($retry_delay) seconds..."
            )
            sleep ($retry_delay | into duration --unit sec)
            continue
          }

          print $"Bucket ($entry.bucket) created"
        }

        print $"Authorizing key ($entry.keyId) for bucket ($entry.bucket)"
        let allow_output = (
          timeout $"($init_timeout)s"
            garage bucket allow
              --read
              --write
              --key (open $entry.keyId | str trim)
              $entry.bucket
        ) | complete

        if $allow_output.exit_code == 0 {
          print $"Key ($entry.keyId) authorized for bucket ($entry.bucket)"
          break
        }

        if $attempt == $max_attempts {
          garage make error {
            msg: (
              $"Failed to authorize key ($entry.keyId) for bucket ($entry.bucket)"
              + $" after ($max_attempts) attempts"
              + $":\n($allow_output.stderr)"
            )
          }
        }

        print (
          $"Bucket allow ($entry.bucket) attempt ($attempt) failed"
          + $" with stdout '($allow_output.stdout)'"
          + $" and stderr '($allow_output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }

    print "All buckets initialized"
  }

  def "garage make error" [msg] {
    error make {
      msg: ($msg | to json)
    }
  }

  def "garage handle error" [e] {
    let data = $e.msg | from json
    if ($data | describe) == "string" {
      print -e $e.msg
    } else {
      print -e $data.msg
    }
    exit 1
  }
}
