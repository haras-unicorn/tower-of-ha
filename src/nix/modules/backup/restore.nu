def "main restore {{TOH_RESTORE_TYPE}}" [] {
  let cwd = pwd
  let work_dir = mktemp -d
  let pass_file = [ $work_dir pass ] | path join
  let age_file = [ $work_dir age-private ] | path join
  let data_dir = $"($work_dir)/data"
  mkdir $data_dir

  let backups = ls
    | where type == dir
    | get name
    | where { str starts-with backup }
    | sort --reverse
  if ($backups | length) == 0 {
    print -e "No backups found"
    exit 1
  }
  let backup_dir = $backups | first | path expand
  cd $backup_dir

  if ($in | is-empty) {
    $in | save -f $pass_file
  } else if not ("pass" | path exists ) {
    (systemd-ask-password
      --emoji=no
      --echo=no
      --timeout=0
      'Enter backup passphrase:') | save -f $pass_file
    printf "%s" "$PASS" > "$WORK_DIR/pass"
  } else {
    cp -f pass $pass_file
  }

  with-env {
    SSH_TO_AGE_PASSPHRASE: (cat $pass_file)
  } {
    ssh-to-age -private-key -i ssh-private -o $age_file
  }

  age -d -i $age_file -o $"($work_dir)/backup.tar.gz" backup.tar.gz.age
  mkdir $data_dir
  tar -xzf $"($work_dir)/backup.tar.gz" -C $data_dir

  cd $data_dir
  nu -c `
    {{{TOH_RESTORE_COMMANDS}}}
  `

  cd $cwd
  rm -rf $work_dir
  echo $"Restore complete from '(basename $backup_dir)'."
}
