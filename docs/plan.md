# Plan

This is the plan that turns Tower Of HA from a proof of concept into something
that runs on real machines. The [design](./design.md) says what we are building.
This page says where the code stands and in what order we change it.

How to read it:

- The work is split into **steps**, in the order below.
- Each step is split into **chunks**. One chunk is one change that can be
  reviewed on its own. A chunk is done when it is reviewed and committed on
  `fix/modernize`. Most steps land in one big pull request, with CI off (see the
  [design](./design.md#decisions)).
- Each chunk says what it does and how we know it is done.
- Sizes are rough: **S** is an evening, **M** a few sessions, **L** more than a
  week. They are guesses, and will get better after step 1.

## Order

**Decided** on 2026-11-16. Changed on 2026-11-17: the move to containers went
from step 1 to step 2, because step 1 leaves the tests alone. Changed on
2026-11-18: the deployable suite went from step 1 to the end, because it adds
friction while the services and cryl still change.

1. Modernize: haraspkgs, fix the nasty patterns.
2. Containers, and tests independent of the services (originally step 6).
3. Matrix.
4. Observability.
5. Remove Nebula.
6. Swap HAProxy for Envoy.
7. Behavior and invariant tests.
8. Chaos engineering.
9. CLI.
10. ACL.
11. Workflow tests.
12. A deployable suite, with an example cluster (originally part of step 1).

The service-independent tests come right after step 1, so that every later step
(new services, swapped services) has a contract to pass. The step numbers below
follow this order, not the original one.

## Where it stands

Read on 2026-11-16, on `main` (commit `9967a64`). Each finding says how sure it
is:

- **checked**: confirmed by running something.
- **read**: seen in the code, not run.

### Blockers

These stop the stack from being used at all.

- **Tests do not evaluate (checked).** The CLI puts `pkgs.vault` on its path
  (`src/nix/modules/cli/cli.nix:41`). Vault is HashiCorp's BSL-licensed build
  and unfree, so nixpkgs refuses it. `nix flake check --no-build` stops at the
  first NixOS test (`test-services-authelia`) with this error. That may also be
  why the Synapse test never passed. The fix is `pkgs.openbao` and `bao`.
- **No way to build a real machine (read).** The flake exports no NixOS modules,
  and `flake.lib` is always empty (`src/nix/lib/default.nix:6` filters on a
  marker no value sets). The modules work only inside tests.
- **Machines need test code to boot (read).** Two things a machine cannot work
  without are defined only in test modules:
  - passing `toh.meta.sops.secrets` to sops-nix
    (`src/nix/test/secrets.nix:193`),
  - the base definitions of the `toh-*-online` targets
    (`src/nix/test/targets.nix`).

### Security

- **The age key fetch trusts the whole LAN (read).** `fetch-age-key` scans the
  local subnets for port 42069 and takes the first answer over `curl -k`, with
  no certificate check (`src/nix/modules/openbao/secrets.nu:97`). The serving
  side does not exist. The fetch itself stays (decided). The certificate check
  is part of the OpenBao work, see [Parked](#parked).
- **OpenBao serves plain HTTP (read).** `tls_disable = true`
  (`src/nix/modules/openbao/default.nix:66`). The same holds for several
  backends behind the proxy: Authelia, ddns-updater, Forgejo HTTP, Garage, LLDAP
  and Vaultwarden take plain HTTP from HAProxy across machines. That breaks
  invariant 4.
- **OpenBao keeps its own root material (read).** On init it stores the root
  token and recovery keys in its own key-value store (`init.nu`,
  `openbao upload ... $root_key $root`). That breaks invariant 2. They belong in
  the cluster sops file.
- **OpenBao init cannot recover (read).** If any step after `bao operator init`
  fails, the error handler exits before the root token is saved, so the token is
  lost and init cannot be run again (`openbao handle error` calls `exit 1`
  inside every `catch`).
- **Secrets on command lines (read).** `toh deploy` passes the SSH private key,
  the sudo password and the age key inside `ssh` and `bash -c` arguments
  (`src/nix/modules/cli/deploy.nu`), where `ps` and logs on both ends can see
  them.
- **Backend ports are open to the whole VPN (read).** The firewall opens service
  ports on every interface, so any VPN member can skip the proxy. Step 10 closes
  this.

### Bugs

- **The token timer runs the wrong unit (read).** It starts
  `openbao-fetch-two-hour-token.service`, but the service is
  `openbao-fetch-token` (`src/nix/modules/openbao/token.nix`). The token is
  never refreshed and runs out after two hours.
- **The age key shred forgets a file (read).** It shreds the age key twice and
  never the response file (`src/nix/modules/openbao/secrets.nu`,
  `openbao shred age key`).
- **`makePath` with a base path fails (read).** `lib.removePrefix basePath` is
  missing its second argument (`src/nix/lib/url.nix`), so any HTTP endpoint with
  a `path` throws when turned into a URL. There are no unit tests for `url.nix`.
- **Named overlays are broken (read).** `composeOverlayAttrs` calls
  `transitiveDeps` and `composeOverlay` with one argument too few
  (`src/nix/lib/overlay.nix`). Only the `default` overlay works. The `nixos` and
  `flake` option descriptions are also swapped. All of this goes away with
  haraspkgs.
- **CLI (read).** `toh machine pick` forgets a `return`, so it always loads
  secrets. `toh flake` fails when `TOH_FLAKE` is unset. `deploy` and `image`
  call `sshpass`, `deploy`, `nixos-generate` and `guestfish`, which are not on
  the CLI's path. Most commands in the README (`status`, `backup`, `ssh`, `sql`,
  `mount`) do not exist.
- **DNS zones by the last two labels (read).** `tohLib.dns.routeToIp` puts
  `test.co.uk` into zone `co.uk`, and the unit tests expect it
  (`src/nix/lib/dns.nix`).

### Patterns to replace

- **Our own copy of haraspkgs.** `toh.lib`, `toh.overlays`, `runToHTest`,
  `writeNushellApplication`, `flake-root`, `renderMustacheTemplate` and the dev
  shell all have haraspkgs versions now.
- **`dev test` commits for you.** Every `dev test` command runs `git add .` and
  `git commit -m wip` (`src/nix/dev/test.nu`). That is where the long runs of
  `wip` commits come from. A `git+file` flake only needs files to be tracked.
- **Patched nixpkgs at eval time.** Two small patches (an option in
  `security/ca.nix`, one Python dependency for Ceph) make every evaluation
  import a patched copy of nixpkgs, twice with unstable. Both can be a module
  override and an `overrideAttrs` instead.
- **Modules that add overlays.** NixOS modules set `toh.overlays`, and the CLI
  is put together by gluing script text from every module into one file. Each
  machine gets its own CLI, and none of it can be tested on its own.
- **Library helpers that read machine config.** `serviceMachines` and friends
  live in `toh.lib` but depend on the NixOS config they are evaluated in.
- **HAProxy leaks into `toh.meta`.** The HAProxy module fills `toh.meta.proxies`
  and `toh.meta.relays` with its own port scheme (TCP services at port + 10000).
- **Magic values.** Ports, timeouts, retry counts and token lifetimes are
  constants inside modules and scripts, not options.
- **Style.** `with` (2 files), `rec` (4 files), bare builtins (a few), `TODO`
  comments (21, listed in [todo.md](./todo.md)), and the name `machinea`.
  `toh.meta.machine.version` is the state version and is pinned to `25.11` in
  tests.

### Container readiness

A first sort of the 26 test files. Not tried yet, so all of it is **read**.

- **Should move as is:** authelia, cli, coredns, ddns-updater, etcd, forgejo,
  garage, haproxy, journald, lldap, maddy, openbao, openssh, patroni, pki, sssd,
  valkey, vaultwarden, and the plain `test` test.
- **Need work:**
  - easytier and nebula need a TUN device in the container. Moved on 2026-11-19:
    containers get `/dev/net/tun` from the host.
  - chronyd cannot set the clock in a container. Its test could check config and
    sync status only, or stay a VM.
  - networkmanager and geoclue need a closer look.
- **Probably stay VMs:**
  - cephfs: OSDs on loop devices, FUSE mounts. Moved on 2026-11-18: OSDs keep
    their data in a plain file, and containers get `/dev/fuse` from the host.
  - samba: CTDB moves IP addresses. Gone since 2026-11-18: one smbd runs at a
    time, behind an etcd lease (`toh.leases`).
- **Test helpers:** `src/nix/test/machine.nix` sets QEMU options (memory, cores,
  `kvm-clock`) and reads `virtualisation.test.*`. They split into container
  defaults and VM defaults.

### Stale docs and tooling

- The README says to join with the TailScale client, lists Postfix and Dovecot
  (the code uses Maddy) and Fluentd and OpenSearch (not built yet), and shows
  CLI commands that do not exist.
- `CONTRIBUTING.md` calls the dev command `dev-toh`. It is `dev`.
- `AGENTS.md` differs between `main` and `matrix`, and neither describes the
  haraspkgs layout we are moving to.
- `opencode.json` is still in the repository.
- CI is off: `nix flake check` is commented out in
  `.github/workflows/check.yaml`. That stays so for now, on purpose.

## Step 1: Modernize

Make the flake workable. Done when the flake evaluates on haraspkgs and nothing
in it is unfree. The NixOS tests are left alone and may break on the way. Step 2
brings them back.

1. **Design docs (S).** This plan, the design and [todo.md](./todo.md), with the
   answers from the first review.
2. **haraspkgs flake and dev shell (M).** `makeFlake` over `src/nix`, the dev
   shell as a dev module, generated repository files, the `dev` CLI from
   haraspkgs. `dev test` stops committing. Done when `dev check` and
   `dev format` pass.
3. **`self.lib` and `self.overlays` (M).** Replace `toh.lib` and `toh.overlays`,
   delete our overlay graph and its tests, use the haraspkgs Nushell and
   mustache helpers. Modules stop adding overlays. Done when every unit test
   passes as `self.unitTests`. **Done**, except that modules still add CLI parts
   through the NixOS option `toh.overlays`, now composed with the haraspkgs
   graph helpers. Its redesign is [parked](#parked).
4. **One nixpkgs (S).** Replace the two nixpkgs patches with a module override
   and an `overrideAttrs`, and drop the patched import. Done when nothing
   imports nixpkgs at eval time beyond the flake input.
5. **Free software only (S).** `vault` becomes `bao`, the flake's own `pkgs`
   stops setting `allowUnfree = true` (`src/nix/overlays/nixpkgs/default.nix`),
   and a check fails when anything in the flake is unfree (invariant 1). Done
   when that check passes.
6. **NixOS module suite.** Moved to [step 12](#step-12-deployable-suite). Chunk
   3 already exports every module as `self.nixosModules`.
7. **Style and small bugs (M).** `with`, `rec`, bare builtins, `machinea`, the
   stale state version. The `makePath` and DNS zone bugs, each with a unit test.
8. **Docs (S).** README, CONTRIBUTING, AGENTS, a Diátaxis layout for this book,
   generated option docs, and [todo.md](./todo.md) kept up to date.

## Step 2: Containers and service-independent tests

Done when every test runs again, as containers where it can, and every
capability has a contract test that every current implementation passes.

1. **Container harness (M).** Port the test helpers to `self.nixosTests`
   containers, with a separate VM path for the tests that need it. Pilot with
   etcd. Done when the etcd test passes as containers. **Done.** Until cryl
   supports containers, the secrets test module forces the machines cryl sees.
2. **Move the tests (L).** Every test from the "should move" list, one or a few
   per chunk. The rest get a written reason to stay VMs. Done when
   `nix flake check` passes. The tests without helper servers moved on
   2026-11-18. Forgejo stays a VM, because it keeps its repositories on CephFS.
3. **The last VMs (M, spike).** Try to move the tests that are left to
   containers. Ceph is the most valuable, because forgejo and samba need it too.
   - Ceph: **done.** OSDs on BlueStore with a plain file instead of a loop
     device, and `ceph-fuse` instead of the kernel mount. `/dev/fuse` comes from
     the host's `extra-sandbox-paths`. cephfs, samba and forgejo run as
     containers; only the optional kernel mount test stays a VM.
   - chronyd: **done.** The checked test runs as containers with `chronyd -x`,
     and the optional `services-chronyd-clock` VM test sets the real clock.
4. **Implementation-free meta (M).** Move HAProxy's port scheme out of
   `toh.meta.proxies` and `toh.meta.relays`, and check every capability's meta
   options for other leaks. **Done** on 2026-11-18: `toh.meta.proxy` works out
   the proxy addresses and relays, HAProxy only serves them. The only other leak
   was the `forgejo` default of `toh.meta.git.ssh.user`. It comes before the
   contract shape, so the contracts are written against the final meta.
5. **Contract shape (S).** Write down how a contract test module looks,
   following `toh.test.mesh` and `toh.test.relay`: it takes the implementation
   as a parameter and checks only behavior. **Done** on 2026-11-19, in the
   [design](./design.md#capabilities-and-contracts).
6. **One contract per chunk (M each).** VPN (exists), DNS, proxy, database,
   key-value, S3, LDAP, OIDC, email, git, file sharing, secrets, time. Each
   chunk writes the happy path of one contract in the shape from chunk 5, plugs
   in every current implementation, and fixes what the separate client finds,
   like credentials that are only made on the machines of the service. The VPN
   chunk moves `toh.test.mesh` and `toh.test.relay` to the new shape.
   - Database: **done** on 2026-11-19, with Patroni. A machine that registers an
     app now installs its credentials, and the Patroni machines only make them
     and keep the init secret. The contract replaces `services-patroni-app`.
   - Key-value: **done** on 2026-11-19, with Valkey. The ACL file stays on the
     Valkey machines, and `toh.meta.kv.instances` got the user name.
   - S3: **done** on 2026-11-19, with Garage. Garage machines keep their own
     copy of the app keys to import them.
   - LDAP: **done** on 2026-11-19, with LLDAP, which needed no change.
   - DNS: **done** on 2026-11-19, with CoreDNS, which now opens port 53. The
     client runs without the DNS helper and resolves a node name.
   - Proxy: **done** on 2026-11-19, with HAProxy, which needed no change. The
     client offers a service and reaches it back through the proxy.
   - Email: **done** on 2026-11-19, with Maddy. `toh.meta.email` got submission
     and IMAP endpoints, the HAProxy certificate names every proxy host, and
     Maddy makes mailboxes for every app of the cluster and delivers by local
     part.
   - OIDC: **done** on 2026-11-19, with Authelia, which needed no change. The
     client reads the discovery document and pushes an authorization request
     with its secret, because a login needs a browser.
   - Files: **done** on 2026-11-19, with CephFS, as the `filesystem` contract. A
     second client mounts the directory of the first and reads back what the
     first wrote. The first version used two mounts on one client, which a local
     filesystem also passes.
   - VPN: **done** on 2026-11-19, with EasyTier and Nebula. `toh.test.mesh` and
     `toh.test.relay` became the `mesh` and `relay` networks of the `vpn`
     contract, and run as containers with `/dev/net/tun` from the host.
   - Git: **done** on 2026-11-19, with Forgejo. Apps get local Forgejo users
     through `toh.meta.git.users`, and pushing creates a repository.
   - File sharing: not started. Samba has no `toh.meta` options for a client. It
     needs a design first.
   - Time: not started. It comes with the
     [intranet goal](./design.md#intranets), which has no step yet.
   - Secrets: parked with OpenBao.

## Step 3: Matrix

1. **Failover design (S).** The main process holds an etcd lease. Decide where
   the workers run ([open question 2](./design.md#open-questions)) on paper
   first.
2. **Synapse (L).** Bring the module over from the `matrix` branch, onto the new
   base, with the failover from chunk 1. It must pass a new chat contract.
3. **Clients and federation (M).** Well-known files, federation through the
   proxy, a web client if we want one.

## Step 4: Observability

1. **Pick the stack (S).** Logs and metrics that fit on Pis
   ([open question 1](./design.md#open-questions)).
2. **Build it (L).** Collection on every machine, storage in HA, a contract
   test.

## Step 5: Remove Nebula

1. **Remove (S).** Module, tests, cryl generators, docs. EasyTier stays the only
   VPN and keeps passing the VPN contract.

## Step 6: Envoy instead of HAProxy

1. **Envoy module (L).** Passes the proxy contract from step 2: HTTP routing by
   host, TCP passthrough, the mail submission port, health checks, TLS to every
   backend.
2. **Remove HAProxy (S).**

## Step 7: Behavior and invariant tests

1. **Invariant checks (M).** Tests for each invariant in the design: no unfree
   packages, TLS on every hop, secret file permissions, sops-only secrets, open
   ports.
2. **Behavior tests (L).** Per service: it does what it says (send and read a
   mail, push to git, log in through SSO), not only "the unit is running".

## Step 8: Chaos engineering

1. **Faults (L).** Kill a machine, split the network, skew the clock, fill a
   disk, restart in the wrong order. Each finding either hardens a module or
   goes into the docs as a known pitfall.

## Step 9: CLI

1. **Structure (M).** One CLI package with commands per area, testable on its
   own, instead of script text glued together from modules.
2. **Commands (L).** Secrets (runs cryl, see the design's secrets flow),
   install, deploy, status, ssh, sql, backup and restore. No secrets on command
   lines. This also fixes the CLI bugs found above.

## Step 10: ACL

1. **Model (M).** Declare who may reach what in the shared module.
2. **Enforce (L).** With the three levers from the [design](./design.md#scope):
   EasyTier rules for the network, Envoy rules for services, OpenBao policies
   for secrets, and nftables on each machine where EasyTier cannot express a
   rule. Backend ports closed to everything but their clients.

## Step 11: Workflow tests

1. **Lifecycle (L).** Tests that drive the CLI through the first install, adding
   and removing a machine, switching configurations, renewing secrets and
   restoring a backup, with the invariants checked after every step.

## Step 12: Deployable suite

Done when an example cluster built from `nixosModules.default` evaluates a
`nixosConfiguration` per machine. Until then the sops-nix wiring and the targets
live only in the test modules, so invariant 6 does not hold yet.

1. **Machine basics in the suite (M).** Move the sops-nix wiring and the base
   `toh-*-online` targets out of the test modules and into the suite, and wire
   in cryl the way its flake module expects at that time.
2. **Example cluster (M).** Written the way a user would: one shared module, one
   module per machine, and `toh.meta.cluster.machines` filled from all of them,
   under `self.nixosConfigurations`.

## Parked

- The `matrix` branch, until step 3.
- **Vaultwarden as an example.** Dropped from the suite on 2026-11-18, because
  it is an app on top of the stack and not part of it. It comes back later as
  the example of how to turn software that is not distributed into a highly
  available service, in a way that is simple for users to repeat.
- **Redesign the NixOS-level `toh.overlays`.** Modules still add CLI parts as
  overlays that depend on the machine config. That is hard to read, and setting
  `nixpkgs.overlays` in a machine means tests and containers cannot use a
  read-only `pkgs`. Probably goes with the CLI structure in step 9.
- **Drop the CA module copy (bonus, much later).** Since step 1,
  `src/nix/modules/pki/ca.nix` is a copy of nixpkgs' `security/ca.nix` with one
  change, because `security.pki.caBundle` is read-only and every nixpkgs module
  reads its CA certificates from it. The copy has to follow nixpkgs. Keeping it
  is acceptable; a way around it that is not worse would be nicer. The Ceph
  rebuild that was parked with it is gone since 2026-11-18: only `cephfs-shell`
  needed `distro`, and its service gets it through `PYTHONPATH`.
- **A flake when containers start.** Sometimes systemd in one container fails to
  start a process ("Failed to spawn executor: No such file or directory"). The
  targets of that machine then fail, and later the test driver loses it
  ("Transport endpoint is not connected"). Seen in maddy and Patroni on
  2026-11-18; both passed on a re-run. Find out whether it comes from ToH or
  from the nixpkgs container tests, and fix it here or in nixpkgs.
- **Simplify the services.** Much of the service code repeats itself. Move the
  shared parts into `self.lib`, with unit tests there, and keep the modules
  thin.
- **OpenBao fixes**, in a step not picked yet: TLS, keeping root material out of
  OpenBao, recovering from a failed init, the token timer, the shred, and the
  certificate check on the age key fetch.
- Modernizing cryl, which is its own project. Changes that ToH needs from cryl
  (like a fix for `config.flake.cyrl` in its flake module, which is misspelled
  on both `v0.4.1` and `main`) go there as issues.
