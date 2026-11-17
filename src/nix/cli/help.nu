# Get help from ToH CLI
def main []: nothing -> nothing {
  exec nu -c $"(toh file) --help"
}

# Get help from ToH CLI
def "main help" []: nothing -> nothing {
  exec nu -c $"(toh file) --help"
}
