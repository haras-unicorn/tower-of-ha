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
friction while the services and cryl still change. Changed on 2026-11-21: step 6
(Envoy) comes right after step 5 and before step 4, so that observability
collects the stats of Envoy and not of HAProxy, which goes away.

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

**Closed** on 2026-11-19. Every capability has its contract and each contract
passed on its own. The human runs the full `nix flake check` after this, and its
result is not recorded here; a failure in it is a bug to fix on the way, not a
reason to reopen the step.

**Changed** on 2026-11-19, after closing. The full `nix flake check` could not
run: `--max-jobs 1` and `--no-build` made no difference, because it evaluates
every NixOS test in one process (about 50 GB), so the problem is evaluation and
not the running of the tests. The tests stopped being flake checks. They are
`lib.<system>.nixosTests.<name>`, and the new `dev test` builds them in separate
processes, as many at once as `--jobs` says (one by default). CI runs
`dev check`, `nix flake check` and `dev test`. "Done when `nix flake check`
passes" in chunk 2 now reads as "done when `dev test` passes". On its first run
on the human's machine, memory went up and down with each test instead of piling
up. Whether a full run passes is not recorded here.

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
   - File sharing: **done** on 2026-11-19, with Samba, as the `share` contract.
     `toh.meta.share` has apps and shares like the git meta. The Samba machines
     make a user and a CephFS directory per app, and set the Samba passwords
     under the samba lease. A second client reads what the first wrote.
   - Time: **done** on 2026-11-19, with chronyd. A machine can serve time
     (`toh.meta.time.serve`), the others take it from the serving machines, and
     the contract asks each server over NTP. The intranet goal that follows from
     it is in [todo.md](./todo.md).
   - Secrets: **done** on 2026-11-19, with OpenBao. The contract is that the
     `bao` CLI works: a client uses the token its machine fetched, then writes
     and reads the secret of its machine. The token service now defaults to on
     for every machine of a cluster with OpenBao, and the proxy is named
     `secrets`. The OpenBao init is unchanged, and its problems stay
     [parked](#parked).

   Every capability in the list above has its contract now.

## Step 3: Matrix

Not blocked since 2026-11-19, when the failover was decided: the main process
holds an etcd lease and the workers run on every machine (see the
[design](./design.md#decisions)).

1. **Failover design (S).** **Decided** on 2026-11-19. What is left is the
   worker roles that allow only one instance, like the one for background tasks:
   for each, whether it takes the lease with the main process or is sharded
   across machines. That goes in the Synapse chunk.
2. **Synapse (L).** Bring the module over from the `matrix` branch, onto the new
   base, with the failover from chunk 1. It must pass a new chat contract. On
   2026-11-20 it split in two, because the proxy routes HTTP by host only and a
   Synapse worker serves only some URL paths, so workers cannot get traffic
   until the proxy can route by path:
   1. **Main process on the lease (M).** The `chat` meta, the `chat` contract,
      the module ported to the new base, and a test that the main process moves
      to another machine when the holder of the lease stops. The signing key is
      made from a cluster secret, so it is the same on every machine, and the
      media store is a CephFS mount, so both survive a failover. Apps get a chat
      user and a room that the lease holder makes. Databases can ask for a
      locale (`dbLocale`), because Synapse refuses a database that is not `C`;
      the database contract checks it. The singleton worker roles stay on the
      main process, so they move with the lease, and sharding is left for much
      later. **Done** on 2026-11-20: `contracts-chat-synapse` and
      `services-synapse` pass. The first run found two bugs outside the Synapse
      code. The CephFS mounts named their systemd unit wrong for a path with a
      dash in it, so `toh-filesystem-online.target` never came up, and the
      default Synapse port, 8008, is the one Patroni's REST API uses. The Ceph
      mount tests now mount a path with a dash, and Synapse listens on 8090.
   2. **Path routing (M).** An `http` or `https` endpoint can have a `route` (no
      other protocol has the option): paths of the proxy address of another
      service, as prefixes or regular expressions, with a `priority` that sorts
      the routes of an address (the lowest number first, the service name only
      breaks a tie). It is in the proxy meta, the HAProxy module and the proxy
      contract, so Envoy has to pass the same contract in
      [step 6](#step-6-envoy-instead-of-haproxy). **Written** on 2026-11-20:
      `contracts-proxy-haproxy` passes, with a prefix route, a regular
      expression route that must match the whole path, and two routes of one
      path that only the priority tells apart. The human's `nix flake check` and
      proxy and HAProxy tests passed on it. After review the `route` moved from
      the service onto its HTTP and HTTPS endpoints, and the unit tests were
      changed to match.
   3. **Workers (L).** **Decided** on 2026-11-20: one generic worker process per
      machine, for the sync and read paths of the client API and for inbound
      federation, reached through a `route`. No media worker, because several
      media workers must share one server and one of them runs the background
      jobs, so the main process keeps the media. Workers reach the main process
      through the proxy and through Valkey. Our nixpkgs has a `workers` option,
      but its units require a local main process and it only accepts a local
      replication listener, so the worker unit is our own. In three pieces:
      1. **Plumbing, no workers yet.** **Done** on 2026-11-20. The main process
         uses Valkey as a `kv` app over TLS, has a replication listener
         registered as the proxied service `synapse-replication`, and reads a
         new cluster secret for `worker_replication_secret`. `services-synapse`
         now has Valkey in its cluster and checks, before and after a failover,
         that the main process connects to Redis and that the replication
         listener answers through the proxy. `contracts-chat-synapse` passes
         too.
      2. **The worker on every machine,** with its own unit that does not need
         the local main process, a route and a health check. The test checks
         that a request through the proxy is handled by a worker, also after the
         main process moved. **Done** on 2026-11-20, together with piece 3:
         `matrix-synapse-worker` runs on every Synapse machine and reaches the
         main process at the `synapse-replication` proxy address over TLS. It
         takes the sync, read and event sending paths of the client API and the
         read paths of federation, from the list in the Synapse docs. Logins,
         pagination, media and inbound federation transactions stay on the main
         process (see [todo.md](./todo.md)). `services-synapse` waits for the
         worker on every machine and checks in the access logs that a client
         request before the failover and a federation request after it were
         answered by a worker and not by the main process. In
         `contracts-chat-synapse` the message goes in through a worker, which
         hands it to the main process over replication. That run found two bugs.
         The workers send the name of the main process as the host header, so
         the proxy found no backend for replication by host;
         `synapse-replication` became a TCP service with TLS termination. And
         the contract retried its login with every other step, and the retries
         kept it over the login rate limit of Synapse forever; each client now
         logs in once and retries only the steps after it.
      3. **Federation paths** on the same worker. Done with piece 2.
3. **Clients and federation (M).** Well-known files, federation through the
   proxy, a web client if we want one. **Done** on 2026-11-20, in two pieces:
   1. **Element.** `services-element` serves Element from every machine behind
      its own proxy address and checks that its config names the chat.
      Federation with the internet was split off on the way, because nothing
      outside the VPN can reach the cluster; that is public ingress, in
      [todo.md](./todo.md), with a Tuwunel spike next to it.
   2. **Ready to federate.** `toh.meta.chat.serverName`, the server well-known
      file, no trusted key servers and allowed private ranges, as in the
      [design](./design.md#decisions). `services-synapse-federation` runs a
      plain Synapse outside the cluster from a new test helper
      (`toh.test.matrix`) and checks that a user of each server reads what the
      other wrote in one room. The run found three bugs outside Synapse. HAProxy
      matched the whole host header, and Matrix servers send the port in it, so
      they got 503; the proxy contract now sends a host with a port. The DNS
      test helper answered a name it does not have with a server failure, which
      Synapse takes as an error when it looks for SRV records; it serves zone
      files now. And it put several addresses of one name on one line.

**Closed** on 2026-11-20. `contracts-chat-synapse`, `services-synapse`,
`services-synapse-federation`, `services-element`, `contracts-proxy-haproxy` and
`services-ddns-updater-duckdns` pass; the full `dev test` has not run on it.

## Step 4: Observability

1. **Pick the stack (S).** Logs and metrics that fit on Pis
   ([open question 1](./design.md#open-questions)). **Done** on 2026-11-21:
   Prometheus, Thanos Query, Alertmanager and a Matrix bridge, logs stay in
   journald, Falco later, no dashboards. See the design decision.
2. **Metrics (M).** The `metrics` capability: machines declare what can be
   collected from them, Prometheus on any number of machines collects all of it,
   and Thanos Query answers at the proxy address. Machine metrics from the node
   exporter and the stats of Envoy. A contract test. **Done** on 2026-11-24:
   written on 2026-11-21 together with chunk 3, because the agent's sandbox
   cannot download the packages, and every test passed on the human's first run.
   On the way:
   - Each copy of Prometheus has a Thanos sidecar, which is how Thanos Query
     reads it, and Thanos Query runs next to every copy behind the proxy as
     `thanos-query`.
   - Envoy serves only the stats of its admin interface on a port of their own,
     because the admin interface can also change and stop the proxy.
   - Envoy adds two alerts, a service without a healthy backend and many
     requests turned away (401 or 403), and the node exporter adds a disk or
     memory almost full and a failed unit.
   - `services-prometheus` checks that every machine is counted once, also after
     one copy stops.
3. **Alerts (M).** Services declare alerts in the meta, Alertmanager on any
   number of machines sends each once, and the bridge posts it into the room of
   the chat app `alerts`. A contract test for the alerts, and a service test
   that sees an alert arrive in the room. **Done** on 2026-11-24, with chunk 2.
   `services-alertmanager-matrix` failed once under `--jobs 6` and passed on its
   own. On the way:
   - Prometheus gets its whole configuration as text, because the nixpkgs module
     cannot drop the label of the copy from the alerts, and without that
     Alertmanager would send each alert once per copy.
   - Chat apps can `invite` users into their room, so the person who should get
     the alerts is asked in with `toh.services.alertmanager.matrix.invite`. No
     test covers the invite yet.
   - The alerts contract runs without the bridge, so it needs no Synapse.
4. **Falco (L).** Package it, then run it on every machine with its findings as
   metrics, so they become alerts like the rest. **Done** on 2026-11-24, and
   both tests passed on their first run. On the way:
   - No packaging: nixos-unstable has both the package and a NixOS module, so
     ToH takes both from there until NixOS 26.11 has them. The container plugin
     it loads is built from source too.
   - A match of a rule of priority error or higher is a critical alert, any
     other match a warning. Falco counts a rule only from its first match on, so
     the alert also takes a counter that is new since a window ago.
   - Containers cannot load the eBPF probe, so `services-falco` runs Falco
     without a driver and only checks its metrics. `services-falco-alerts` is a
     skipped VM test where reading `/etc/shadow` has to become an alert.

## Step 5: Remove Nebula

1. **Remove (S).** Module, tests, cryl generators, docs. EasyTier stays the only
   VPN and keeps passing the VPN contract. **Done** on 2026-11-21. The module
   folder held the module, its cryl generations and its three VPN contract
   tests, so it went as a whole. Outside it, only the test defaults named it
   (for `/dev/net/tun`), and its two TODOs left [todo.md](./todo.md). The
   generators themselves are part of cryl and stay there.
   `toh.meta.domains.machineSecret` stays, because EasyTier and ddns-updater use
   it too.

## Step 6: Envoy instead of HAProxy

1. **Envoy module (L).** Passes the proxy contract from step 2: HTTP routing by
   host and by path (step 3 adds the routes of a service: prefixes and regular
   expressions that match the whole path, tried by priority), TCP passthrough,
   the mail submission port, health checks, TLS to every backend. Envoy's
   regular expressions are RE2, which is why the meta asks for that subset.
   **Written** on 2026-11-21, in one go with the human's go-ahead, and not run
   yet, because building Envoy needs downloads the agent's sandbox cannot make.
   On the way:
   - The ten `services-haproxy-*` tests became the `balancing` variants of the
     proxy contract (`selfLib.test.proxyTests` makes the whole set for an
     implementation), so Envoy passes exactly what HAProxy passed. With HAProxy,
     `contracts-proxy-haproxy`, `-http-http-http` and `-tcp-passthrough-http`
     pass; the client now reaches the servers through the proxy from outside,
     where the old tests asked from the servers.
   - Health checks expect plain text, no regular expressions: Envoy's TCP check
     sends once and then looks for each expected text in order. No service used
     a regular expression, so `selfLib.regex` and `selfLib.types.regexOrString`
     are gone. Valkey's three commands now go in one send.
   - Envoy never sends to every backend when most are unhealthy (its "panic"
     default), because Valkey has one healthy backend out of many.
   - Persistence hashes the source address or a cookie, where HAProxy kept a
     table, so a client may move when a backend leaves.
   - Every service test runs with Envoy.

   **Run** on 2026-11-21 by the human: every proxy contract test with Envoy
   passes, and so does the full suite apart from the three Synapse tests. Two
   things came up:
   - The nixpkgs `envoy` package builds from source and downloads its whole
     Bazel toolchain, JDKs included, so the module uses `envoy-bin` for now.
   - Envoy refuses to start on a regular expression whose compiled size is over
     100, and some Synapse worker routes are. The limit is now the tunable
     `toh.services.envoy.maxRegexSize`, 1000 by default. The three Synapse tests
     pass with it.

2. **Remove HAProxy (S).** After every test passes with Envoy, so HAProxy stays
   the reference while Envoy is debugged. **Done** on 2026-11-21: the module and
   its contract tests went as a whole, and nothing else used it. Of its entries
   in [todo.md](./todo.md), the locality weighting (now on the Envoy module) and
   UDP for time moved under "Not placed yet". The one about traffic reaching
   backends before their first health check went away: Envoy holds a backend
   back until its first check passes, and the kv contract, which saw that happen
   with HAProxy, passes with Envoy.

## Step 7: Behavior and invariant tests

1. **Invariant checks (M).** Tests for each invariant in the design: no unfree
   packages, TLS on every hop, secret file permissions, sops-only secrets, open
   ports. **Done** on 2026-11-24: `src/nix/test/invariants.nix` checks every
   machine of every test. Every non-VM test passed with the checks of
   permissions, ports and unfree packages; the sops, least privilege and TLS
   checks came later and ran on five of them. On the way:
   - Only invariants 1 to 4 are checks. High availability is for step 8, and the
     others are about how the code is written.
   - Invariant 2 is checked as far as a test sees it: no secret a machine
     decrypts turns up in the store closure of the machines. Invariant 3 fails
     only on a secret of another machine; the leftovers a machine makes on the
     way to its own secrets only show up in the log, until cryl can list exact
     keys. Invariant 4 only shows plain ports in the log, until every hop is
     TLS. Both have a `strict` switch for then.
   - Values everyone may read, like the CA certificate, are `public` in
     `toh.meta.sops.secrets`, so the permission checks leave them alone.
   - The checks found and fixed: the RPC portal of EasyTier and the gRPC of
     Thanos Query on network addresses, the STUN server of the VPN test on TCP,
     and the job cache of the Forgejo runner on random ports, which is off for
     now.
   - UDP ports that EasyTier opens by hole punching stay closed in the firewall,
     so processes in `toh.meta.network.holePunchers` are left out of the port
     check.
   - The skipped VM tests have not run with the checks yet.
2. **Behavior tests (M).** Per service, write down what its tests show it does
   (send and read a mail, push to git, log in through SSO), beyond "the unit is
   running". The holes this finds are filled in step 8. **Done** on 2026-11-24,
   in [what the tests show](./behavior.md), from reading every test and without
   changing one. What it found:
   - Only Samba, Synapse and Prometheus have a failover test. Patroni, Valkey,
     etcd, CephFS and Garage, which hold the data of everything else, do not.
     These go to the faults of chunk 8.1, the other holes to chunk 8.2.
   - The tests of geoclue, NetworkManager, the Forgejo runner and OpenBao
     (beyond its contract) only show that units start, and backup has no test.
   - `services-patroni-init` runs the same script as `services-patroni`.
   - Most holes are a second step after a contract: a login through Authelia,
     git over SSH, an app that may not read the data of another.

## Step 8: Chaos engineering

1. **Faults (L).** Kill a machine, split the network, skew the clock, fill a
   disk, restart in the wrong order. Each finding either hardens a module or
   goes into the docs as a known pitfall.
   - Started on 2026-11-25, after the decisions on what the faults check (see
     the [design](./design.md#decisions)). The full suite first showed seven
     tests broken by the invariant checks of step 7.1: servers made copies of
     app secrets they never use, and the store check took template lines for
     secrets. Both are fixed.
   - `src/nix/test/faults.nix` holds the shared faults, for now `fault_kill` and
     `fault_revive`. A killed container gets SIGKILL on its init from outside,
     because the test driver has no `crash()` for containers.
   - The database contract kills every server once, so the one that takes the
     writes goes too, and checks that every confirmed write is still there and
     that writes work again. Patroni passes it with strict synchronous
     replication and `pg_rewind`, both new.
2. **Test hardening (L).** Ensure each and every test has builtin retries and
   such so that it is not flaky. This is important because we want to be
   absolutely sure that what is being tested is the failure and not the test.
   Fill the behavior holes found in step 7 too, listed in
   [what the tests show](./behavior.md).

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
