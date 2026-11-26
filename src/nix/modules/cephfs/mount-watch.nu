let mounts = r#'{{{TOH_CEPHFS_MOUNT_WATCH_MOUNTS}}}'# | from json
let interval = r#'{{{TOH_CEPHFS_MOUNT_WATCH_INTERVAL}}}'# | into int | into duration --unit sec
let timeout = r#'{{{TOH_CEPHFS_MOUNT_WATCH_TIMEOUT}}}'#

# Mounts every CephFS mount again whose client is gone, like one that the
# metadata servers evicted while the machine was cut off, and starts again
# what ran on it
def main [] {
  loop {
    for mount in $mounts {
      let probe = probe $mount.path
      if (gone $probe) {
        print $"($mount.path) fails: ($probe.stderr | str trim)"
        mount again $mount
      }
    }
    sleep $interval
  }
}

# NOTE: the listing needs the metadata servers, unlike a statfs, which the
# monitors still answer for a client that the metadata servers evicted
def probe [path: string] {
  do { ^timeout $timeout ls --all $path } | complete
}

# NOTE: a client that is gone fails at once, with whatever error; a mount
# that only takes long, like while the metadata servers fail over, runs into
# the timeout and is left alone
def gone [probe: record<stdout: string, stderr: string, exit_code: int>] {
  let timed_out = 124
  $probe.exit_code != 0 and $probe.exit_code != $timed_out
}

# NOTE: the units that need the mount stop with it, and nothing starts them
# again, so the ones that ran are started again after it; a unit that runs
# only on the holder of a lease then comes back only on that holder
def "mount again" [mount: record<path: string, unit: string>] {
  print $"the client of ($mount.path) is gone, so it is mounted again"
  let running = ^systemctl list-dependencies --reverse --plain $mount.unit
    | lines
    | skip 1
    | each { |line| $line | str trim }
    | where { |unit| (do { ^systemctl is-active --quiet $unit } | complete).exit_code == 0 }
  do { ^umount --lazy $mount.path } | complete | ignore
  ^systemctl restart $mount.unit
  if not ($running | is-empty) {
    ^systemctl start ...$running
  }
}
