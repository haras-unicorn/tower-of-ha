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
  mkdir $"($directory)/network"
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
      if (cut off $live) {
        print "fewer than half of the relays answer, so other machines get no answer"
      }
      $answered = $live
    }
    sleep $interval
  }
}

def "live relays" [] {
  $relays | where { |relay|
    let url = $"http://($relay):($health_port)($health_path)"
    (do { ^curl --silent --fail --output /dev/null --max-time $timeout $url } | complete).exit_code == 0
  }
}

# NOTE: a machine that reaches fewer than half of the relays is more likely
# cut off than the others are gone, and it would send other machines only to
# itself, so it gives them no answer and they ask another nameserver
def "cut off" [live: list<string>] {
  ($live | length) * 2 < ($relays | length)
}

# NOTE: queries from this machine get only its own relay, at localhost, while
# it answers; clients keep their connections, and one kept to the relay of
# another machine hangs for good when that relay freezes, because its kernel
# still acknowledges; only while its own relay does not answer does this
# machine get the others; queries from other machines never get localhost,
# which is not their relay; an answer without relays helps no program on this
# machine, so then it gets every relay
def "write zones" [live: list<string>, serial: int] {
  let reachable = if ($live | is-empty) { $relays } else { $live }
  let local = if $own_ip in $live {
    ["127.0.0.1"]
  } else if $own_ip in $reachable {
    ["127.0.0.1"] | append $reachable
  } else {
    $reachable
  }
  for zone in $zones {
    let network = $"($directory)/network/($zone).zone"
    if (cut off $live) {
      rm --force $network
    } else {
      write zone $zone $network $live $serial
    }
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
