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
    $".#checks.x86_64-linux.\"test-($test)\".withSshBackdoor"
    --option sandbox-paths /dev/vhost-vsock
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
    $".#checks.x86_64-linux.\"test-($test)\".withSshBackdoor.driverInteractive"
    --option sandbox-paths /dev/vhost-vsock
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
