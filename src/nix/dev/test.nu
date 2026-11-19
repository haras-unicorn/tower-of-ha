def main [
  --jobs (-j): int = 1
  --filter (-f): string = ""
  --skipped
] {
  if $jobs < 1 {
    error make { msg: "--jobs must be at least 1" }
  }

  let flake = $"git+file://(pwd)"
  let system = ^nix eval --impure --raw --expr builtins.currentSystem
  let tests = $"($flake)#lib.($system).nixosTests"

  let selected = ^nix eval --json $tests --apply builtins.attrNames
    | from json
    | where {|name| $name =~ $filter }
  if ($selected | is-empty) {
    error make { msg: $"no test matches '($filter)'" }
  }

  let results = $selected | par-each --keep-order --threads $jobs {|name|
    let skip = if $skipped {
      false
    } else {
      ^nix eval --json $"($tests).($name).skipped" | from json
    }

    if $skip {
      print $"-- ($name): skipped"
      { name: $name, status: "skipped" }
    } else {
      print $"== ($name)"
      let passed = try {
        ^nix build --no-link --print-build-logs $"($tests).($name)"
        true
      } catch {
        false
      }
      { name: $name, status: (if $passed { "passed" } else { "failed" }) }
    }
  }

  let passed = $results | where status == "passed" | length
  let skipped = $results | where status == "skipped" | length
  let failed = $results | where status == "failed" | get name

  print ""
  print $"($passed) passed, ($failed | length) failed, ($skipped) skipped"
  if not ($failed | is-empty) {
    print ($failed | each {|name| $"  ($name)" } | str join "\n")
    exit 1
  }
}
