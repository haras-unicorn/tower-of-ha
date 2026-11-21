def main [] {
  let settings = r#'{{{TOH_ALERTMANAGER_MATRIX}}}'# | from json

  let token = login $settings
  let room_id = find-room $settings $token

  let matrix = $settings.config.matrix | merge {
    "user-id": $settings.userId
    "access-token": $token
    "room-mapping": ({} | insert $settings.roomName $room_id)
  }

  $settings.config
    | merge { matrix: $matrix }
    | to json
    | save --force $settings.output
}

def login [settings: record] {
  let response = (
    http post --full --allow-errors --content-type application/json
      $"($settings.url)/_matrix/client/v3/login"
      {
        type: "m.login.password"
        identifier: { type: "m.id.user", user: $settings.user }
        password: (open --raw $settings.password | str trim)
      }
  )

  if $response.status != 200 {
    error make { msg: $"cannot log in as ($settings.user): ($response.body | to json --raw)" }
  }

  $response.body.access_token
}

def find-room [settings: record, token: string] {
  let alias = $settings.room | url encode --all
  let response = (
    http get --full --allow-errors
      --headers { Authorization: $"Bearer ($token)" }
      $"($settings.url)/_matrix/client/v3/directory/room/($alias)"
  )

  if $response.status != 200 {
    error make { msg: $"cannot find the room ($settings.room): ($response.body | to json --raw)" }
  }

  $response.body.room_id
}
