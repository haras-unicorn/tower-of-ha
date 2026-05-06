def "main backup {{TOH_BACKUP_TYPE}}" [] {
  let cwd = pwd
  let export_dir = $"($cwd)/backup-(date now | format date "%Y_%m_%d-%H_%M_%S")"
  mkdir $export_dir
  let work_dir = mktemp -d
  let data_dir = $"($work_dir)/data"
  mkdir $data_dir

  cd $data_dir
  nu -c `
    {{{TOH_BACKUP_COMMANDS}}}
  `

  cd $work_dir
  openssl rand -base64 6 > pass # NOTE: 6 for 8 characters
  let pass = $"(cat pass)"

  ssh-keygen -a 100 -t ed25519 -C backup -N $pass -f ./ssh
  mv ssh ssh-private
  mv ssh.pub ssh-public
  ssh-to-age -i ssh-public -o age-public
  with-env { SSH_TO_AGE_PASSPHRASE: $pass } { ssh-to-age -private-key -i ssh-private -o age-private }
  tar -C $data_dir -czf - . | age -R age-public > backup.tar.gz.age

  mv ssh-public ssh-private backup.tar.gz.age $export_dir
  cd $cwd
  rm -rf $work_dir

  echo $"Backup created at '($export_dir)' with password '($pass)'"
}
