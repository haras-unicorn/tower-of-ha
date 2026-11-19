let users = r#'{{{TOH_SAMBA_USERS}}}'# | from json

# NOTE: smbpasswd asks for the password twice and reads it from standard
# input with -s, so it never shows up in the process list; -a adds the user or
# sets the password of a user that exists
def main [] {
  for user in $users {
    let password = open --raw $user.password | str trim
    let result = $"($password)\n($password)\n" | smbpasswd -a -s $user.name | complete
    if $result.exit_code != 0 {
      error make { msg: $"Failed to set the Samba password of ($user.name): ($result.stderr)" }
    }
    print $"Set the Samba password of ($user.name)"
  }
}
