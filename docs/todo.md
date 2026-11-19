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

## Step 5: Remove Nebula

These go away with the Nebula module.

- `src/nix/modules/nebula/default.nix:1`: turn firewall rules into Nebula
  firewall rules.
- `src/nix/modules/nebula/default.nix:2`: block all traffic from outside Nebula.

## Step 6: Envoy instead of HAProxy

- `src/nix/modules/haproxy/default.nix:1`: proxy to the other proxies over TLS
  when the service is not on this machine, and to localhost when it is. Weight
  the backends by locality: this machine first, then the rack, the datacenter,
  the region and other regions. Envoy has locality-weighted load balancing built
  in.
- `src/nix/modules/haproxy/default.nix`: right after start, HAProxy sends
  connections to backends whose first health check has not run yet. The kv
  contract saw writes land on a Valkey replica. Envoy should hold back until a
  backend passed its first check.
- `src/nix/meta/time.nix`: free HAProxy does not play well with UDP proxying,
  which Envoy does, so once Envoy carries UDP, check whether time can use
  `toh.meta.services` and the proxy and drop its own meta.

## Step 7: Behavior and invariant tests

- `src/nix/modules/maddy/test.nix:27`: actually send and read a mail, once
  himalaya v2 is out.
- `src/nix/test/defaults.nix`: the global test timeout of 300 seconds, and the
  `timeout=` of the waits in the test scripts, are magic numbers. Put them in
  `self.lib.test` and use them from there.

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
- `dev test` runs the tests in series. A CI matrix with one job per test name
  would be faster, if the runners can take it.

## Parked: OpenBao fixes

- `src/nix/modules/openbao/default.nix:1`: TLS for the HA cluster.

## Not placed yet

Service work that fits no step so far.

- **Intranets (needs more thinking).** ToH should also run in an intranet, where
  only a little traffic goes in and out. A few relay machines would reach the
  outside for what cannot be done fully inside, like time, and the other
  machines would get it from them. Nothing is designed yet. Things to work out:
  which relays, what else besides time they serve, and what ToH itself reaches
  on the outside today (the public time servers in `chronyd`, and the public
  STUN servers EasyTier uses when `stunServers` is unset).
- `src/nix/meta/filesystem.nix:1`: more than one file system instance.
- `src/nix/modules/cephfs/default.nix:1`: real disks for the OSDs.
- `src/nix/modules/cephfs/default.nix:2`: more than one file system instance.
- `src/nix/modules/chronyd/default.nix:3`: turn on NTS after the first sync.
- `src/nix/modules/coredns/default.nix:1`: DNSSEC and DNS over TLS.
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
- `src/nix/modules/valkey/default.nix:1`: replace the static `bootstrapPrimary`
  with a post-start script that finds the current primary through Sentinel, so
  no node has to be picked as the first primary.
- `src/nix/modules/valkey/apps.nix:77`: remove the duplicated permissions.
