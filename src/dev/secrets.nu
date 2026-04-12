# TODO: figure out sandbox

def "main secrets rotate" [host?: string, --all] {
  let artifacts = [(flake-root) "artifacts"] | path join
  rm -rf $artifacts
  mkdir $artifacts
  cd $artifacts
  (if $all { toh host all } else { [ (toh host pick $host) ] }) | each {
    nix eval --json $"(flake-root)#cryl.($in.configuration)"
      | cryl from-stdin json --allow-script --allow-net --stay --nosandbox
  }
}
