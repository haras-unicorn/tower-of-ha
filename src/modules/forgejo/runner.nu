let config_template = r#'{{{TOH_FORGEJO_RUNNER_CONFIG_TEMPLATE}}}'#
let config_path = r#'{{{TOH_FORGEJO_RUNNER_CONFIG_PATH}}}'#
let secret = r#'{{{TOH_FORGEJO_RUNNER_SECRET}}}'#
let machine_name = r#'{{{TOH_FORGEJO_RUNNER_MACHINE_NAME}}}'#
let user = r#'{{{TOH_FORGEJO_RUNNER_USER}}}'#
let group = r#'{{{TOH_FORGEJO_RUNNER_GROUP}}}'#
let db = r#'{{{TOH_FORGEJO_RUNNER_DB_INSTANCE}}}'# | from json

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --timeout: int = 30,
] {
  let id = try {
    forgejo fetch runner id
  } catch { |e|
    forgejo handle error $e
    exit 1
  }

  (mustache-renderer
    --variables (
      {
        TOH_FORGEJO_RUNNER_ID: $id
        TOH_FORGEJO_RUNNER_SECRET: (open --raw $secret)
      } | to toml
    )
    --template $config_template
    --out $config_path
    --chmod 400
    --chown $"($user):($group)")

  def "forgejo fetch runner id" [] {
    print $"Fetching ($machine_name) runner id..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($timeout)s"
          usql (open --raw $db.url) -c $"
            SELECT id
            FROM __toh_action_runners
            WHERE name = '($machine_name)'
          "
      ) | complete

      if $output.exit_code == 0 {
        let id = $output.stdout | str trim
        print $"Runner id '($id)' fetched for ($machine_name) successfully"
        return $id
      }

      if $attempt == $max_attempts {
        forgejo make error {
          msg: (
            $"Failed to fetch ($machine_name) runner id after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Runner id for ($machine_name) record attempt ($attempt) failed"
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
