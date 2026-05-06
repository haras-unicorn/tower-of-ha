let age_key_paths_per_machine = "{{{TOH_AGE_KEY_PATHS_PER_MACHINE}}}" | from json

def "main deploy" [machine?: string] {
  let machine = toh machine pick --with-secrets $machine
  let age_key_path = $age_key_paths_per_machine | get $machine.name
  let age_key_dir = $age_key_path | path dirname
  if ($machine.name == (open --raw /etc/hostname | str trim)) {
    sudo mkdir -p $age_key_dir
    sudo chmod 700 $age_key_dir
    $machine.secrets."age-private" | sudo tee $age_key_path
    sudo chmod 400 $age_key_path
    sudo nixos-rebuild switch --flake $"(toh flake)#($machine.name)"
  } else {
    ssh-agent bash -c $"
      echo '($machine.secrets."ssh-private")' \\
        | ssh-add - \\
      && export SSHPASS='($machine.secrets."pass-priv")' \\
      && sshpass -e ssh ($machine.meta.network.ip) sudo bash -c '
        mkdir -p \"($age_key_dir)\" \\
        && chmod 700 \"($age_key_dir)\" \\
        && echo \"($machine.secrets."age-private")\" \\
          | sudo tee \"($age_key_path)\" \\
        && chmod 400 \"($age_key_path)\"
      ' \\
      && sshpass -e deploy \\
        --skip-checks \\
        --interactive-sudo true \\
        --hostname ($machine.meta.network.ip) \\
        -- '(toh flake)#($machine.name)' \\
    "
  }
}

def "main image" [machine?: string, --format: string] {
  let wd = pwd
  let tmp = mktemp -d
  cd $tmp

  let machine = toh machine pick --with-secrets $machine
  let age_key_path = $age_key_paths_per_machine | get $machine.name
  let format = if $format == null { "sd-aarch64" } else { $format }

  let raw = (nixos-generate
    --show-trace
    --system $machine.system.nixpkgs.system
    --format $format
    --flake $"(toh flake)#($machine.configuration)")

  let compressed = ls ($raw
    | path dirname --num-levels 2
    | path join "sd-image")
    | get name
    | first
  unzstd $compressed -o image.img
  chmod 644 image.img

  let age = $machine.secrets."age-private"
    | str replace -a "\\" "\\\\"
    | str replace -a "\n" "\\n"
    | str replace -a "\"" "\\\""

  let commands = $"run
mount /dev/sda2 /
mkdir-p /root
chmod 700 /root
write \"($age_key_path)\" \"($age)\"
chmod 400 \"($age_key_path)\"
exit"

  echo $commands | guestfish --rw -a image.img
  mv image.img $wd

  cd $wd
  rm -rf $tmp
}
