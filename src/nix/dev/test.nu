# Run all ToH tests
def main []: nothing -> nothing {
  (nix flake check
    --option max-jobs (max-jobs)
    --keep-going
    --all-systems)
  nix-unit --flake .#tests
}

# Run one ToH NixOS test (run with --no-eval-cache if the store complains)
def --wrapped "main nixos" [
  # Test name
  test: string,
  # Additional "nix build" arguments
  ...args: string
]: nothing -> nothing {
  (nix build
    $".#checks.(current-system).\"test-($test)\".withSshBackdoor"
    --option extra-sandbox-paths /dev/vhost-vsock
    ...$args)
}

# Run every ToH NixOS test matching a regex
def --wrapped "main nixos regex" [
  # Test name regex
  regex: string,
  # Additional "nix build" arguments
  ...args: string
]: nothing -> nothing {
  let system = current-system
  let checks = (nix eval --json $".#checks.($system)" --apply builtins.attrNames
    | from json
    | where { $in =~ $"test-($regex)" }
    | each { $".#checks.($system).\"($in)\"" })
  (nix build
    --option max-jobs (max-jobs)
    --keep-going
    ...$checks
    ...$args)
}

# Run one ToH NixOS test interactively
def --wrapped "main nixos interactive" [
  # Test name
  test: string,
  # Additional "nix run" arguments
  ...args: string
]: nothing -> nothing {
  (nix run
    $".#checks.(current-system).\"test-($test)\".withSshBackdoor.driverInteractive"
    --option extra-sandbox-paths /dev/vhost-vsock
    ...$args)
}

# Run the ToH unit tests whose output matches a filter
def --wrapped "main unit" [
  # Filter for the test output
  test: string,
  # Additional "nix-unit" arguments
  ...args: string
]: nothing -> nothing {
  nix-unit --flake ".#tests" ...$args out+err>| grep $test
}

def current-system []: nothing -> string {
  nix eval --impure --raw --expr builtins.currentSystem
}

def max-jobs []: nothing -> string {
  [1 ((sys cpu | length) / 4 | math floor)] | math max | into string
}
