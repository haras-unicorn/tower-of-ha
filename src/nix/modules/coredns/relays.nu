let relays = r#'{{{TOH_COREDNS_RELAYS_ALL}}}'# | from json
let own_ip = r#'{{{TOH_COREDNS_RELAYS_OWN_IP}}}'#
let zones = r#'{{{TOH_COREDNS_RELAYS_ZONES}}}'# | from json
let directory = r#'{{{TOH_COREDNS_RELAYS_DIRECTORY}}}'#
let health_port = r#'{{{TOH_COREDNS_RELAYS_HEALTH_PORT}}}'#
let health_path = r#'{{{TOH_COREDNS_RELAYS_HEALTH_PATH}}}'#
let interval = r#'{{{TOH_COREDNS_RELAYS_INTERVAL}}}'# | into int | into duration --unit sec
let timeout = r#'{{{TOH_COREDNS_RELAYS_TIMEOUT}}}'#
let ttl = r#'{{{TOH_COREDNS_RELAYS_TTL}}}'#

# Writes the zones of the relays that answer their health check, once at
# start and then whenever that changes, and tells systemd it is ready after
# the first write, so CoreDNS never starts without its zones
def main [] {
  mut answered = null
  mut serial = 0
  loop {
    let live = live relays
    if $live != $answered {
      $serial = [(date now | format date "%s" | into int), ($serial + 1)] | math max
      write zones $live $serial
      if $answered == null {
        ^systemd-notify --ready
      }
      print $"the relays that answer: ($live | str join ', ')"
      $answered = $live
    }
    sleep $interval
  }
}

# NOTE: an answer without relays helps no client, and no relay answering is
# more likely a fault of this machine than of all of them, so then the answer
# has every relay
def "live relays" [] {
  let live = $relays | where { |relay|
    let url = $"http://($relay):($health_port)($health_path)"
    (do { ^curl --silent --fail --output /dev/null --max-time $timeout $url } | complete).exit_code == 0
  }
  if ($live | is-empty) { $relays } else { $live }
}

# NOTE: queries from this machine get its own relay first, at localhost, and
# queries from other machines never get localhost, which is not their relay
def "write zones" [live: list<string>, serial: int] {
  let local = if $own_ip in $live { ["127.0.0.1"] | append $live } else { $live }
  for zone in $zones {
    write zone $zone $"($directory)/($zone).zone" $live $serial
    write zone $zone $"($directory)/($zone).local.zone" $local $serial
  }
}

def "write zone" [zone: string, path: string, ips: list<string>, serial: int] {
  let records = $ips | each { |ip| [$"@ ($ttl) IN A ($ip)" $"* ($ttl) IN A ($ip)"] } | flatten
  [
    $"$ORIGIN ($zone)."
    $"@ ($ttl) IN SOA ns.($zone). hostmaster.($zone). ($serial) ($ttl) ($ttl) ($ttl) ($ttl)"
    $"@ ($ttl) IN NS ns.($zone)."
    ...$records
  ] | str join "\n" | $in + "\n" | save --force $"($path).new"
  mv --force $"($path).new" $path
}
