def "toh flake" [] {
  if (which flake-root | length) > 0 {
    flake-root
  } else {
    "github:haras-unicorn/toh"
  }
}
