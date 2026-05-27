# Search the LDAP directory via ldapsearch
def --wrapped "main ldap search" [...args: string] {
  if $env.USER != root and $env.USER != lldap {
    print -e "Requires root or lldap user"
    exit 1
  }

  let machine = toh machine current --with-secrets

  let base_args = if ($args | any { $in == "-b" }) {
    [ ]
  } else {
    [ -b ($machine.meta.ldap.baseDistinguishedName) ]
  }

  (ldapsearch -LLL
    -H $machine.meta.ldap.url
    -D $machine.meta.ldap.adminDistinguishedName
    -w ($machine.secrets | get lldap-admin-pass)
    ...($base_args)
    ...($args))
}

# Add a user to the LDAP directory
def "main ldap user add" [
    username: string
    password: string
    email: string
    --display-name: string
    --uid-number: int
    --gid-number: int
    --home-directory: string
    --unix-shell: string
] {
    if $env.USER != root and $env.USER != lldap {
      print -e "Requires root or lldap user"
      exit 1
    }

    let machine = (toh machine current --with-secrets)
    let lldap_host = $machine.meta.proxies.lldap.endpoint.https.host
    let lldap_port = $machine.meta.proxies.lldap.endpoint.https.port
    let base_url = $"https://($lldap_host):($lldap_port)"

    let auth = {
      username: admin
      password: ($machine.secrets | get lldap-admin-pass)
    } | to json
    let auth_response = (curl -s -X POST $"($base_url)/auth/simple/login"
      -H "Content-Type: application/json"
      -d $auth)
      | complete
    if $auth_response.exit_code != 0 {
      print -e $"Authentication failed ($auth_response.exit_code): ($auth_response.stderr)"
      exit 1
    }
    let auth_resp = $auth_response.stdout | from json
    if ($auth_resp | describe) == "string"  {
      print -e $"Authentication failed: ($auth_resp)"
      exit 1
    }
    if ($auth_resp | get token? | is-empty) {
      print -e $"Authentication failed: ($auth_resp)"
      exit 1
    }
    print "Authenticated as admin."
    let token = $auth_resp.token

    let attrs = (
      (if $uid_number != null { [{ name: "uidNumber", value: [($uid_number | into string)] }] } else { [] })
      | append (if $gid_number != null { [{ name: "gidNumber", value: [($gid_number | into string)] }] } else { [] })
      | append (if $home_directory != null { [{ name: "homeDirectory", value: [($home_directory)] }] } else { [] })
      | append (if $unix_shell != null { [{ name: "unixShell", value: [($unix_shell)] }] } else { [] })
    )
    let display_name = if ($display_name | is-empty) { $username } else { $display_name }
    let variables = {
      user: {
        id: $username
        email: $email
        displayName: $display_name
        firstName: $username
        lastName: $username
      }
    }
    let variables = if ($attrs | length) > 0 {
      $variables | upsert user.attributes $attrs
    } else {
      $variables
    }
    let query = "mutation CreateUser($user: CreateUserInput!) { createUser(user: $user) { id } }"
    let payload = { query: $query, variables: $variables } | to json
    let create_response = (curl -s -X POST $"($base_url)/api/graphql"
      -H $"Authorization: Bearer ($token)"
      -H "Content-Type: application/json"
      -d $payload)
      | complete
    if $create_response.exit_code != 0 {
      print -e $"Creating user failed ($create_response.exit_code): ($create_response.stderr)"
      exit 1
    }
    let create_resp = $create_response.stdout | from json
    if ($create_resp.errors? | is-not-empty) {
      print -e $"Creating user failed: ($create_resp.errors | to json)"
      exit 1
    }
    print $"User ($username) created."

    let set_password_response = (lldap_set_password
      --base-url $base_url
      --token $token
      --username $username
      --password $password)
      | complete
    if $set_password_response.exit_code != 0 {
      print -e $"Setting password failed ($set_password_response.exit_code): ($set_password_response.stderr)"
      exit 1
    }
    print $"Password set for ($username)."
}
