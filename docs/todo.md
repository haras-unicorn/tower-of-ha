# To do

The `TODO` comments from the code, collected on 2026-11-17. The coding style
says they become issues. They live here for now, because most of them get fixed
in the one big pull request (see the [design](./design.md#decisions)). When one
is fixed, its comment and its entry here go away together.

They are sorted by the [plan](./plan.md) step that is likely to fix them.

## Step 1: Modernize

- `src/nix/meta/cluster.nix:16`: `toh.meta.cluster.machines` uses `types.raw`.
  It should use the real NixOS configuration type.

## Step 2: Containers and service tests

Found while fixing the tests, not `TODO` comments.

- `src/nix/modules/cephfs/default.nix`: `keyType` only changes the allowed
  ciphers. The keys still come from cryl, which the kernel test wraps to make
  aes keys.
- `src/nix/modules/patroni/init.nix`: every Patroni machine runs the init at the
  same time, and when the `alter user ... with password` statements race
  (`tuple concurrently updated`), Postgres logs the failed statement with the
  superuser passwords into the journal.
- `src/nix/modules/forgejo/apps.nu` and `auth.nu`: the Forgejo CLI takes
  passwords and the OAuth client secret only as arguments, so they show up in
  the process list of the Forgejo machine while the init runs.

## Step 7: Behavior and invariant tests

- `src/nix/test/defaults.nix`: the global test timeout of 300 seconds, and the
  `timeout=` of the waits in the test scripts, are magic numbers. Put them in
  `self.lib.test` and use them from there.
- `src/nix/modules/forgejo/runner.nix`: the job cache is off, because it listens
  on random ports on every address and its `host` setting does not move them.
  Turn it back on for speed once it can listen on localhost only.
- `src/nix/test/invariants.nix`: the sops file of a machine also holds what the
  machine made on the way to its own secrets (cert requests and configs, the
  `*-input.json` files, `age-public`, the listing of cryl). The `map` listing of
  cryl could name exactly the keys a machine uses, but its Nix type only takes
  absolute paths while the generator reads them relative to its working
  directory. Fix that in cryl first, then list the keys and turn on
  `toh.test.invariants.leastPrivilege.strict`.
- `src/nix/test/invariants.nix`: the TLS check only shows plain ports in the
  log. Turn on `toh.test.invariants.tls.strict` once every hop is TLS. It only
  tries TLS from the first byte and the STARTTLS of Postgres, so SSH and DNS
  show up too, and UDP is not checked.

## Step 10: ACL

- `src/nix/meta/user.nix:1`: more than one user, with ACL.
- `src/nix/modules/openssh/default.nix:1`: accept SSH only from the VPN.
- `src/nix/modules/cephfs/default.nix:3`: ACL for mounts.
- `src/nix/modules/cephfs/mounts.nix`: every machine with a mount gets the
  CephFS admin keyring, so any app machine can read and change the whole
  filesystem. The filesystem contract runs on that today.

## Step 2 leftovers

- `src/nix/test/contracts/time.nix`: the contract queries the servers with
  `chronyd -Q`, which is chrony again. Switch to a client that is not tied to an
  implementation, a plain NTP client. It is fine as chrony for now, and
  `pkgs.ntp` could not be used because its source is not in the store.
- CI now runs `dev test`, which has not run on a CI machine yet. The runner
  needs `/dev/fuse` and `/dev/net/tun` in `extra-sandbox-paths` and enough RAM
  for one test at a time, and it may be too slow. If a hosted runner cannot do
  it, CI goes back to `dev check` and `nix flake check`, and the tests run on
  the human's machine.
- `dev test` runs one test at a time in CI. A CI matrix with one job per test
  name would be faster, if the runners can take it.

## Step 3 leftovers

- `src/nix/modules/synapse`: URL previews are off, because Synapse would fetch
  pages from the internet. Decide if they are wanted, and if so how.
- The chat contract logs in once per client and retries only the steps after the
  login, which fits the default login rate limits of Synapse. Raise them if more
  contracts or apps log in often.
- `src/nix/modules/synapse/default.nix`: the proxy takes plain HTTP to the
  backend, like the other services, which breaks invariant 4 until the Envoy
  step. The replication listener of the main process is the same: Synapse only
  speaks plain HTTP there, so the workers reach it through the proxy. The plan
  for the whole stack is that every service thinks it talks plain HTTP, TCP or
  UDP, and only the proxies talk to each other across machines, so that only
  proxy ports have to be open and each machine is a bubble. The proxy has to
  enforce it before invariant 4 holds.
- `src/nix/modules/synapse/worker.nix`: the worker takes only the paths that any
  instance can serve. Inbound federation transactions
  (`/_matrix/federation/v1/send/`) should go to one process per remote server,
  and pagination (`/messages`) has to stay on one process per room, so both go
  to the main process for now. `/sync` goes to the workers round robin, though
  it is cheaper when a user stays on one worker. All three need the proxy to
  balance by source address, by room or by user.
- `src/nix/modules/synapse/config.nix`: the `kv` app of Synapse has
  `prefix = "all"`, so it can read every key and channel of its database. Narrow
  it in the hardening pass.

## Step 4 leftovers

- `src/nix/modules/prometheus/default.nix` and
  `src/nix/modules/alertmanager/default.nix`: these hops are plain and go
  straight from machine to machine, not through the proxies: Prometheus
  collecting every target, Thanos Query reading the sidecars, Prometheus sending
  to Alertmanager, and the copies of Alertmanager talking to each other. They
  break invariant 4 like the hops behind the proxy, and the same plan fixes
  them: only proxies talk across machines.
- `src/nix/modules/alertmanager/matrix.nix`: the bridge logs in at every start,
  which leaves a new device on its chat user each time, and all bridges share
  that user, so many starts at once can hit the login rate limit of Synapse.
- `src/nix/modules/synapse/apps.nu`: the `invite` of chat apps has no test.
- `src/nix/modules/falco/default.nix`: take Falco from nixpkgs and drop the
  `nixpkgs-unstable` input once NixOS 26.11 is out.
- `src/nix/modules/falco/default.nix`: nobody knows yet how noisy the stock
  rules are on NixOS. Look at the alerts of a real deployment and turn off or
  narrow the rules that fire for normal work.

## Port clashes

- Nothing checks that two services on one machine want different ports. Synapse
  and Patroni both wanted 8008, and Ceph's dashboard and others want 8080, and
  each clash only showed up as a crashed service in a test. There should be a
  mechanism that finds these before anything runs.

## Parked: OpenBao fixes

- `src/nix/modules/openbao/default.nix:1`: TLS for the HA cluster.

## Not placed yet

Service work that fits no step so far.

- `src/nix/modules/samba/default.nix`: every Samba machine makes its own server
  identity (the SID in `secrets.tdb`), since Samba's databases are local. Files
  on CephFS belong to Unix users, so nothing should break, but a Windows client
  may show other owners after a failover. A Windows VM in the tests would need a
  downloaded image and a license, so check it with Samba's own tools instead:
  `net getlocalsid` on every Samba machine, and the owner of a file through
  `smbcacls` from the client before and after a failover. Pin the SID from the
  config if they differ, and try a real Windows client once by hand.
- **A killed container sometimes never stops.** Its init stays a zombie that
  systemd-nspawn does not collect. The kill now fails after `shutdownTimeout`
  and names the parents, but why nspawn hangs is not known yet. It happened in
  two of the four Samba runs that got to the second kill, and in no other test.
- **A dead first nameserver slows every lookup.** The glibc resolver tries the
  nameservers of a machine in order and waits its full timeout on a dead one, so
  a machine whose first CoreDNS is down resolves slowly until it comes back.
  Shorter `options timeout` or a local resolver would fix it.

- **Intranets (needs more thinking).** ToH should also run in an intranet, where
  only a little traffic goes in and out. A few relay machines would reach the
  outside for what cannot be done fully inside, like time, and the other
  machines would get it from them. Nothing is designed yet. Things to work out:
  which relays, what else besides time they serve, and what ToH itself reaches
  on the outside today (the public time servers in `chronyd`, and the public
  STUN servers EasyTier uses when `stunServers` is unset).
- **Public ingress (needs more thinking).** The other side of intranets: letting
  the internet in. Today every service is reachable only from the VPN. To
  federate the chat with the outside, or to open git or email to people outside,
  some machines take connections from the internet, under a public domain, with
  certificates from a public CA. It touches the proxy, DNS and the certificates
  of the whole stack.
- **Alerts that leave the cluster (needs more thinking).** Alerts reach the
  phone through a Matrix room on the cluster's own Synapse. When Synapse or the
  whole cluster is down, the alert about it cannot get out, and silence looks
  like all is well. Something outside the cluster has to notice the silence, for
  example a heartbeat alert that always fires and a watcher outside that
  complains when it stops. It is the same question as intranets and public
  ingress: what goes out of the network and what comes in.
- **Tuwunel instead of Synapse (spike).** Tuwunel is a Matrix server in Rust
  that needs far less memory than Synapse and has no workers, but it keeps its
  data in an embedded RocksDB and cannot use Postgres. It would run like Samba:
  one process behind an etcd lease, with its database on CephFS. Try it as a
  second implementation of the chat contract, and measure RocksDB on the CephFS
  kernel client of real machines (the containers use `ceph-fuse`, which says
  little about speed). Kept Synapse on 2026-11-20, because RocksDB on CephFS may
  be slow and hard to get right.
- `src/nix/meta/filesystem.nix:1`: more than one file system instance.
- `src/nix/modules/cephfs/default.nix:1`: real disks for the OSDs.
- `src/nix/modules/cephfs/default.nix:2`: more than one file system instance.
- `src/nix/modules/chronyd/default.nix:3`: turn on NTS after the first sync.
- `src/nix/modules/node-exporter/default.nix`: there is no alert for a clock
  that drifts. Chrony keeps the clock, and the faults of step 8.1 leave clock
  skew to monitoring, so a machine whose clock runs off should be an alert, for
  example from the timex collector of the node exporter.
- `src/nix/modules/coredns/default.nix:1`: DNSSEC and DNS over TLS.
- `src/nix/modules/coredns/default.nix`: the node domain is served by the hosts
  plugin with `fallthrough` and nothing after it, so a name it does not have
  gets a server failure and not an answer that the name does not exist. The DNS
  test helper had the same problem and serves zone files now. Synapse looking
  for SRV records failed on it.
- `src/nix/modules/synapse/default.nix`: outgoing federation goes from the
  machine straight to the other server and not through the proxy, unlike the
  plan where only proxies talk across machines.
- `src/nix/modules/envoy/default.nix`: proxy to the other proxies over TLS when
  the service is not on this machine, and to localhost when it is. Weight the
  backends by locality: this machine first, then the rack, the datacenter, the
  region and other regions. Envoy has locality-weighted load balancing built in.
- `src/nix/meta/time.nix`: Envoy can proxy UDP, which HAProxy could not, so once
  Envoy carries UDP, check whether time can use `toh.meta.services` and the
  proxy and drop its own meta.
- `src/nix/modules/coredns/default.nix:2`: sort the hosts of a service by
  locality (machine, rack, datacenter, region, other regions) and set a low TTL,
  so caches do not keep a stale order when something goes down.
- `src/nix/modules/authelia/default.nix:1`: get time from an NTP server behind
  the proxy. The comment names Traefik for proxying UDP, which is stale now that
  the proxy is going to be Envoy.
- `src/nix/modules/lldap/default.nix:1`: send app emails through the email
  capability (`toh.meta.email`).
- `src/nix/modules/patroni/default.nix:1`: make the configuration store (etcd)
  configurable.
- `src/nix/modules/pki/default.nix:70`: use hex once cryl supports it. That is a
  cryl issue first.
- `src/nix/modules/valkey/apps.nix:77`: remove the duplicated permissions.
- Once everything goes through the proxies: harden and tune the stack for the
  topology of a deployment on its own, and rewrite the load balancing rules from
  latencies measured while it runs. Only an idea so far.
