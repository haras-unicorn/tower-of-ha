def main [] {
  let settings = r#'{{{TOH_SYNAPSE_APPS}}}'# | from json

  for user in $settings.users {
    ensure-user $settings $user
    ensure-room $settings $user
  }
}

def ensure-user [settings: record, user: record] {
  if (login $settings $user) != null {
    return
  }

  (
    ^register_new_matrix_user
      --config $settings.config
      --password-file $user.password
      --user $user.name
      --no-admin
      $settings.url
  )
}

def ensure-room [settings: record, user: record] {
  let token = login $settings $user
  if $token == null {
    error make { msg: $"cannot log in as ($user.name)" }
  }

  let response = request $"($settings.url)/_matrix/client/v3/createRoom" $token {
    room_alias_name: $user.alias
    name: $"ToH ($user.alias)"
    preset: "private_chat"
  }

  # NOTE: the room of an earlier run has the alias already
  if $response.status != 200 and $response.body.errcode? != "M_ROOM_IN_USE" {
    error make { msg: $"cannot create the room ($user.alias): ($response.body | to json --raw)" }
  }

  if ($user.invite | is-not-empty) {
    let room_id = find-room $settings $user $token
    for invitee in $user.invite {
      invite $settings $room_id $token $invitee
    }
  }
}

def find-room [settings: record, user: record, token: string] {
  let alias = $"#($user.alias):($settings.serverName)" | url encode --all
  let response = (
    http get --full --allow-errors
      --headers { Authorization: $"Bearer ($token)" }
      $"($settings.url)/_matrix/client/v3/directory/room/($alias)"
  )

  if $response.status != 200 {
    error make { msg: $"cannot find the room ($user.alias): ($response.body | to json --raw)" }
  }

  $response.body.room_id
}

def invite [settings: record, room_id: string, token: string, invitee: string] {
  let room = $room_id | url encode --all
  let response = request $"($settings.url)/_matrix/client/v3/rooms/($room)/invite" $token {
    user_id: $invitee
  }

  # NOTE: a user who is in the room or invited already is refused, which is
  # what a later run sees
  if $response.status != 200 and $response.body.errcode? != "M_FORBIDDEN" {
    error make { msg: $"cannot invite ($invitee) to ($room_id): ($response.body | to json --raw)" }
  }
}

def login [settings: record, user: record] {
  let response = request $"($settings.url)/_matrix/client/v3/login" "" {
    type: "m.login.password"
    identifier: { type: "m.id.user", user: $user.name }
    password: (open --raw $user.password | str trim)
  }

  if $response.status == 200 {
    $response.body.access_token
  } else {
    null
  }
}

def request [url: string, token: string, body: record] {
  let headers = if ($token | is-empty) {
    {}
  } else {
    { Authorization: $"Bearer ($token)" }
  }

  http post --full --allow-errors --content-type application/json --headers $headers $url $body
}
