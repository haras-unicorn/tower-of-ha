let age_path = r#'{{{TOH_OPENBAO_AGE_PATH}}}'#
let token_path = r#'{{{TOH_OPENBAO_TOKEN_PATH}}}'#
let response_path = r#'{{{TOH_OPENBAO_RESPONSE_PATH}}}'#
let metadata_path = r#'{{{TOH_OPENBAO_METADATA_PATH}}}'#
let age_key = r#'{{{TOH_OPENBAO_AGE_KEY}}}'#
let machine_name = r#'{{{TOH_OPENBAO_MACHINE_NAME}}}'#
let machines_key = r#'{{TOH_OPENBAO_MACHINES_KEY}}'#
let keys_mount = r#'{{{TOH_OPENBAO_KEYS_MOUNT}}}'#

def "main" [
  command: string,
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --timeout: int = 30,
  --offerers-port: int = 42069
] {
  let commands = [ "shred-age-key" "fetch-age-key" ]
  if not ($commands | any { $in == $command }) {
    print -e $"Unknown command '($command)'"
    print -e $"Available commands are: ($commands | str join ', ')"
    exit 1
  }

  if $command == "shred-age-key" {
    try {
      openbao shred age key
    } catch { |e|
      openbao handle error $e
    }
    exit 0
  }

  if $command == "fetch-age-key" {
    if ($age_path | path exists) {
      print "Age key already exists"
      exit 0
    }

    if ($token_path | path exists) and ($metadata_path | path exists) {
      print "OpenBao token and metadata exist"

      let age_key = try {
        openbao fetch age key from openbao
      } catch { |e|
        openbao handle error $e
        exit 1
      }

      try {
        $age_key | openbao save age key
      } catch { |e|
        openbao handle error $e
        exit 1
      }

      exit 0
    }

    print "OpenBao token and metadata do not exist"
    mut age_key = ""
    loop {
      try {
        $age_key = openbao fetch age key from offerers
        break
      } catch { |e|
        openbao handle error $e
      }

      print (
        "Fetching age keys from offerers failed"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }

    try {
      $age_key | openbao save age key
    } catch { |e|
      openbao handle error $e
      exit 1
    }

    exit 0
  }

  def "openbao fetch age key from offerers" [] {
    let servers = openbao get age key offerers
    if $servers == [ ] {
      print "No offerers found..."
    }

    print "Fetching age key from offerers..."
    for server in $servers {
      for attempt in 1..$max_attempts {
        let output = (
          timeout $"($timeout)s"
            curl -kv $"https://($server)"
        ) | complete

        if $output.exit_code == 0 {
          print "Fetched age key from offerer successfully"
          return ($output.stdout)
        }

        if $attempt == $max_attempts {
          openbao make error {
            msg: (
              $"Failed to fetch age key from offerer after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          }
        }

        print (
          $"Fetching age key from offerer attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
  }

  def "openbao fetch age key from openbao" [] {
    let metadata = open $metadata_path
    let servers = $metadata.servers

    print "Fetching age key from OpenBao..."
    for server in $servers {
      for attempt in 1..$max_attempts {
        let output = with-env {
          BAO_ADDR: $server
          BAO_TOKEN: (open --raw $token_path | str trim)
        } {
          (
            timeout $"($timeout)s"
              bao kv get -format=json $"-mount=($keys_mount)"
                $"($machines_key)/($machine_name)"
          ) | complete
        }

        if $output.exit_code == 0 {
          print "Fetched age key from OpenBao successfully"
          return ($output.stdout
            | from json
            | get data.data
            | get $age_key
            | str trim)
        }

        if $attempt == $max_attempts {
          openbao make error {
            msg: (
              $"Failed to fetch age key from OpenBao after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          }
        }

        print (
          $"Fetching age key from OpenBao attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
  }

  def "openbao get age key offerers" [] {
    ls /sys/class/net/*/device
      | get name
      | path dirname
      | path basename
      | each {
          ip -j addr show dev $in
            | from json
            | each {
                get addr_info
                  | where family == inet
                  | where prefixlen >= 24
                  | select prefixlen broadcast
              }
            | flatten
        }
      | flatten
      | each {
          ((ipcalc $"($in.broadcast)/($in.prefixlen)" --network
            | split row "="
            | last)
            + "/"
            + ($in.prefixlen | into string))
        }
      | each {
          (rustscan
            --addresses $in
            --ports $offerers_port
            --timeout ($timeout * 1000)
            --greppable)
            | lines
            | each { split row " " | first }
        }
      | flatten
      | each { $"($in):($offerers_port)" }
  }

  def "openbao save age key" [] {
    $in | save -f $response_path
    mv $response_path $age_path
    chmod 400 $age_path
    chown root:root $age_path
    print "Age key saved"
  }

  def "openbao shred age key" [] {
    def "openbao shred" [path: path] {
      let result = shred -zu $path | complete

      if $result.exit_code == 0 {
        return
      }

      # NOTE: symlink to /nix/store in tests
      if ($result.stderr | str contains "Read-only file system") {
        rm -f $path
      }
    }

    openbao shred $age_path
    if ($response_path | path exists) {
      openbao shred $age_path
    }
    print "Age key shredded"
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
