# Run all ToH tests
def "main test" []: nothing -> nothing {
  cd (flake-root)
  nix flake check --all-systems
  nix-unit --flake .#tests
}

# Run specified ToH NixOS test
def --wrapped "main test nixos" [
  # Test name
  test: string,
  # Additional "nix build" arguments
  ...args: string
]: nothing -> nothing {
  cd (flake-root)
  (nix build
    $".#checks.(toh current system).\"test-($test)\".withSshBackdoor"
    --option extra-sandbox-paths /dev/vhost-vsock
    ...($args))
}

# Run all ToH NixOS tests matching a regex
def --wrapped "main test nixos regex" [
  # Test name
  regex: string,
  # Additional "nix build" arguments
  ...args: string
]: nothing -> nothing {
  cd (flake-root)
  (nix build
    ...(nix eval --impure --json --expr
      ("builtins.attrNames" +
        $" \(builtins.getFlake \"path:(flake-root)\")"
        + $".checks.(toh current system)")
      | from json
      | where { $in =~ $"test-($regex)" }
      | each { $".#checks.(toh current system).\"($in)\"" })
    ...($args))
}

# Run specified ToH NixOS test interactively
def --wrapped "main test nixos interactive" [
  # Test name
  test: string,
  # Additional "nix run" arguments
  ...args: string
]: nothing -> nothing {
  cd (flake-root)
  (nix run
    $".#checks.(toh current system).\"test-($test)\".withSshBackdoor.driverInteractive"
    --option extra-sandbox-paths /dev/vhost-vsock
    ...($args))
}

# Run specified ToH unit test
def --wrapped "main test unit" [
  # Test name
  test: string,
  # Additional "nix-unit" arguments
  ...args: string
]: nothing -> nothing {
  cd (flake-root)
  nix-unit --flake ".#tests" ...($args) out+err>| grep $test
}
