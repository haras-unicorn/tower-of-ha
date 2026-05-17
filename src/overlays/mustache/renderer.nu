def "main" [
  --template: string
  --template_file: string
  --variables: string
  --variables_file: string
  --out: string
  --chown: string
  --chmod: string
] {
  let variables = ($variables | default "{ }")
    | from json
    | transpose key value
    | each { { key: $in.key value: (open --raw $in.value) } }
    | transpose -ird
    | merge (if $variables_file == null { { } } else {
        open --raw $variables_file | from toml
      })
  let template = ($template | default "")
    + (if $template_file == null { "" } else {
      open --raw $template_file
    })
  if $out == null {
    return (with-env $variables { $template | mo /dev/stdin })
  }
  with-env $variables { $template | mo /dev/stdin } | save -f $out
  if $chown != null { chown $chown $out }
  if $chmod != null { chmod $chmod $out }
}
