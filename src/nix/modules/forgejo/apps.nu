let config = r#'{{{TOH_FORGEJO_CONFIG}}}'#
let users = r#'{{{TOH_FORGEJO_USERS}}}'# | from json

# NOTE: the forgejo cli takes passwords only as arguments, so they show up in
# the process list of the forgejo machine while it runs
def main [] {
  for user in $users {
    let password = open --raw $user.password | str trim
    let created = (
      forgejo admin user create
        --config $config
        --username $user.name
        --email $user.email
        --password $password
        --must-change-password=false
    ) | complete

    if $created.exit_code == 0 {
      print $"Created git user ($user.name)"
      continue
    }

    if not ($"($created.stdout)($created.stderr)" | str contains "already exists") {
      error make { msg: $"Failed to create git user ($user.name): ($created.stderr)" }
    }

    (forgejo admin user change-password
      --config $config
      --username $user.name
      --password $password
      --must-change-password=false)
    print $"Updated git user ($user.name)"
  }
}
