let version = "{{{TOH_VERSION}}}"

# Get ToH CLI name and version
def "main version" []: nothing -> nothing {
  print (toh name)
  print (toh version)
}

def "toh version" [] {
  $version
}
