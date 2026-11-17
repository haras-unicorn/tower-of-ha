let source = r#'{{{TOH_SOURCE}}}'# | from json

def "toh flake" [] {
  if ($env.TOH_FLAKE | is-not-empty) {
    $"path:(flake-root)"
  } else {
    $source.flake
  }
}
