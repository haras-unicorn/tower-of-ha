def main [...names: string] {
  let skipped = r#'{{{skippedJson}}}'# | from json
  let flake = $"git+file://(pwd)"
  let system = ^nix eval --impure --raw --expr builtins.currentSystem
  let tests = $"($flake)#lib.($system).nixosTests"

  let available = ^nix eval --json $tests --apply builtins.attrNames | from json

  let unknown = $names | where {|name| $name not-in $available }
  if not ($unknown | is-empty) {
    error make { msg: $"no such test: ($unknown | str join ', ')" }
  }

  let selected = if ($names | is-empty) {
    $available | where {|name| $name not-in $skipped }
  } else {
    $names
  }

  let results = $selected | each {|name|
    print $"== ($name)"
    let passed = try {
      ^nix build --no-link --print-build-logs $"($tests).($name)"
      true
    } catch {
      false
    }
    { name: $name, passed: $passed }
  }

  let failed = $results | where {|result| not $result.passed } | get name

  print ""
  print $"($results | length) tests, ($failed | length) failed"
  if not ($failed | is-empty) {
    print ($failed | each {|name| $"  ($name)" } | str join "\n")
    exit 1
  }
}
