# Format ToH repository
def "main format" []: nothing -> nothing {
  cd (flake-root)
  prettier --write (flake-root)
  nixfmt ...(fd '.*.nix$' (flake-root) | lines)
}

# Lint ToH repository
def "main lint" []: nothing -> nothing {
  cd (flake-root)
  prettier --check (flake-root)
  nixfmt --check ...(fd '.*.nix$' (flake-root) | lines)
  markdownlint --ignore-path .gitignore (flake-root)
  cspell lint (flake-root) --no-progress
  if $env.NIX_BUILD_TOP? == null {
    if (markdown-link-check
      --config $"(flake-root)/.markdown-link-check.json"
      ...(fd '^.*.md$' (flake-root) | lines)
      | rg -q error
      | complete
      | get exit_code) == 0 {
      exit 1
    }
  }
}
