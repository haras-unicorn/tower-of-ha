# To do

The `TODO` comments from the code, collected on 2026-11-17. The coding style
says they become issues. They live here for now, because most of them get fixed
in the one big pull request (see the [design](./design.md#decisions)). When one
is fixed, its comment and its entry here go away together.

They are sorted by the [plan](./plan.md) step that is likely to fix them.

## Step 1: Modernize

- `src/meta/cluster.nix:16`: `toh.meta.cluster.machines` uses `types.raw`. It
  should use the real NixOS configuration type.

## Step 5: Remove Nebula

These go away with the Nebula module.

- `src/modules/nebula/default.nix:1`: turn firewall rules into Nebula firewall
  rules.
- `src/modules/nebula/default.nix:2`: block all traffic from outside Nebula.

## Step 6: Envoy instead of HAProxy

- `src/modules/haproxy/default.nix:1`: proxy to the other proxies over TLS when
  the service is not on this machine, and to localhost when it is. Weight the
  backends by locality: this machine first, then the rack, the datacenter, the
  region and other regions. Envoy has locality-weighted load balancing built in.

## Step 7: Behavior and invariant tests

- `src/modules/maddy/test.nix:27`: actually send and read a mail, once himalaya
  v2 is out.

## Step 10: ACL

- `src/meta/user.nix:1`: more than one user, with ACL.
- `src/modules/openssh/default.nix:1`: accept SSH only from the VPN.
- `src/modules/cephfs/default.nix:3`: ACL for mounts.

## Parked: OpenBao fixes

- `src/modules/openbao/default.nix:1`: TLS for the HA cluster.

## Not placed yet

Service work that fits no step so far.

- `src/meta/filesystem.nix:1`: more than one file system instance.
- `src/modules/cephfs/default.nix:1`: real disks for the OSDs.
- `src/modules/cephfs/default.nix:2`: more than one file system instance.
- `src/modules/chronyd/default.nix:3`: turn on NTS after the first sync.
- `src/modules/coredns/default.nix:1`: DNSSEC and DNS over TLS.
- `src/modules/coredns/default.nix:2`: sort the hosts of a service by locality
  (machine, rack, datacenter, region, other regions) and set a low TTL, so
  caches do not keep a stale order when something goes down.
- `src/modules/authelia/default.nix:1`: get time from an NTP server behind the
  proxy. The comment names Traefik for proxying UDP, which is stale now that the
  proxy is going to be Envoy.
- `src/modules/lldap/default.nix:1`: send app emails through the email
  capability (`toh.meta.email`).
- `src/modules/patroni/default.nix:1`: make the configuration store (etcd)
  configurable.
- `src/modules/pki/default.nix:70`: use hex once cryl supports it. That is a
  cryl issue first.
- `src/modules/valkey/default.nix:1`: replace the static `bootstrapPrimary` with
  a post-start script that finds the current primary through Sentinel, so no
  node has to be picked as the first primary.
- `src/modules/valkey/apps.nix:77`: remove the duplicated permissions.
