def main [
  --jobs (-j): int = 1
  --filter (-f): string = ""
  --tier: int = 1
  --all (-a): string
  --tail (-t): int = 40
] {
  if $jobs < 1 {
    error make { msg: "--jobs must be at least 1" }
  }
  if $tier < 1 or $tier > 3 {
    error make { msg: "--tier must be 1, 2 or 3" }
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
    let test_tier = ^nix eval --json $"($tests).($name).tier" | from json
    let every_tier = $all != null and $name =~ $all

    if $test_tier > $tier and not $every_tier {
      print $"-- ($name): tier ($test_tier), left out"
      { name: $name, status: "left out" }
    } else {
      print $"== ($name)"
      let started = date now
      let passed = try {
        ^nix build --no-link --print-build-logs $"($tests).($name)"
        true
      } catch {
        false
      }
      let status = if $passed { "passed" } else { "failed" }
      let seconds = ((date now) - $started) / 1sec | math round
      print $"-- ($name): ($status) in ($seconds)s"
      { name: $name, status: $status, seconds: $seconds }
    }
  }

  let passed = $results | where status == "passed" | length
  let left_out = $results | where status == "left out" | length
  let failed = $results | where status == "failed" | get name

  for name in $failed {
    print $"\n== ($name): the last ($tail) lines of its log"
    try {
      ^nix log $"($tests).($name)" | lines | last $tail | str join "\n" | print
    } catch {
      print "no log found"
    }
  }

  let ran = $results | where status != "left out"
  if not ($ran | is-empty) {
    print "\n== how long each test took, longest first"
    $ran
      | sort-by seconds --reverse
      | each {|test| $"  ($test.seconds)s ($test.name) ($test.status)" }
      | str join "\n"
      | print
  }

  print ""
  print $"($passed) passed, ($failed | length) failed, ($left_out) left out"
  if not ($failed | is-empty) {
    print ($failed | each {|name| $"  ($name)" } | str join "\n")
    exit 1
  }
}
