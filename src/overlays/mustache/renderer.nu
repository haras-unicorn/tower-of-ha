def "main" [
  --template: string
  --variables: string
  --out: string
  --chown: string
  --chmod: string
] {
  let variables = if ($variables | path exists) {
    open --raw $variables | from toml
  } else {
    $variables | from toml
  }
  let variables = $variables
    | transpose key value
    | each {
        {
          key: $in.key
          value: (
            if ($in.value | path exists) {
              open --raw $in.value
            } else {
              $in.value
            })
        }
      }
    | transpose -ird
  let template = if ($template | path exists) {
    open --raw $template
  } else {
    $template
  }
  if $out == null {
    return (with-env $variables { $template | mo /dev/stdin })
  }
  with-env $variables { $template | mo /dev/stdin } | save -f $out
  if $chown != null { chown $chown $out }
  if $chmod != null { chmod $chmod $out }
}
