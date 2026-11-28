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

1. **Faults (L).** Break the cluster in the ways it has to survive on its own.
   Each finding either hardens a module or goes into the docs as a known
   pitfall. In every fault, no confirmed write is lost and no two machines take
   writes for the same thing at once (no split brain). The list is the goal, and
   not every service has to go through every fault: where a fault says little
   about a small service, its test may be pragmatic. The faults:
   - Kill each machine. Done, see below.
   - Split the network. Done, see below. Cut one machine off from the other two,
     once for each machine, so the one with the leases and the primaries goes
     too. The cut off machine stops taking writes and the other two carry on.
     Once the split heals, it rejoins and catches up without pulling the cluster
     back to its old data.
   - Freeze a machine. Done, see below. Stop all of its processes for longer
     than the leases last, then let them run again. A primary that wakes up must
     not keep writing as if it still were one. This is the split brain that a
     long pause makes, without any network fault.

   Changed on 2026-11-27: the faults after these three moved to chunk 4, after
   the tiers and the hardening. By then the suite had 91 tests and ran for about
   an hour, and a fault test that hung waited out a global timeout of up to 40
   minutes, so every new fault made it slower still. The new faults come into a
   suite with time budgets.

   Left out on purpose, because monitoring covers them and a container cannot
   fake them well:
   - Clock skew. Containers share the clock of the host, chrony keeps it, and
     the VM test `services-chronyd-clock` checks that chrony sets it. There is
     no alert for a clock that drifts yet, which is in the [to do](./todo.md).
   - A full disk. The `DiskAlmostFull` alert of the node exporter warns first.
   - A slow or lossy network. It costs speed and not correctness, and the kills
     and splits already cover a machine that stops answering.

   What happened:
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
   - Later on 2026-11-25, the same kill went into every contract of a service
     that holds data (`fault_kill_each`), and into `services-etcd`. Each
     implementation says with `redundant` when it can lose a server. The S3,
     LDAP, email, secrets, database, kv, OIDC, git and chat contracts and
     `services-etcd` pass. The filesystem contract passes since the tests wait
     for the graces of CephFS, and the share contract (Samba) since 2026-11-26.
     DNS, time, Prometheus and Alertmanager are left out on purpose. What the
     kills found:
     - Sentinel will not fail over the same primary again for twice its failover
       timeout, 6 minutes by default, so a second kill waited that long. The
       timeout is the tunable `toh.services.valkey.sentinel.failoverTimeout`, 60
       seconds by default.
     - The Valkey config named the bootstrap primary on every start, so a
       machine that came back pulled the cluster back to it. A script now asks
       the other sentinels for the primary first (see the
       [design](./design.md#decisions)). Writing it found two more bugs: a
       Nushell script with only `main` subcommands runs nothing, and a sentinel
       whose kept replicas named the new primary turned that primary into a
       replica of itself.
     - The tests had no check that Valkey replicates at all, and the first kill
       came while the replicas were still in their first sync. Valkey replicates
       after it answers and has no synchronous mode, so the apps that use it can
       lose the last seconds of what they wrote. The primary now refuses writes
       once no replica acknowledged within `toh.services.valkey.replicaMaxLag`,
       and the kv contract writes plainly and waits longer than that before a
       kill (see the [design](./design.md#decisions)).
     - CoreDNS named every relay in a fixed order, so clients that try only the
       first address kept reaching a dead machine. It now names only the relays
       whose Envoy is ready, still in a fixed order. `services-coredns-relays`
       checks it.
     - The contract clients used the static test DNS, which never drops a dead
       relay. They now resolve through CoreDNS when the cluster has it.
     - Forgejo, Synapse and Authelia also keep state in Valkey, so their
       contracts wait for Valkey to be redundant as well before a kill.
     - The metadata servers waited 300 seconds before they freed the files of a
       dead machine's mount. They now wait 60, the tunable
       `toh.services.cephfs.silentClientEviction`.
     - A killed container sometimes never stopped, and the test then waited for
       its global timeout without a word. The kill now fails after
       `toh.test.faults.shutdownTimeout` and says what is left.
     - When the killed server holds the active metadata server, CephFS is gone
       for 80 to 125 seconds: a monitor election, then 60 seconds of
       `mds_beacon_mon_down_grace`, then up to 45 seconds of
       `mds_reconnect_timeout` waiting for the dead machine's mount. A watcher
       of the cluster log in the filesystem and share contracts showed it. Both
       waits are now the tunables `toh.services.cephfs.monitorDownGrace` and
       `reconnectTimeout`, with Ceph's defaults, and the tests of CephFS and of
       what lives on it wait for them on top of the failover time
       (`toh.test.faults.failoverDelay`).
     - On 2026-11-26, Samba still failed: after a kill, every login on the new
       machine hung on a lock in Samba's own databases, which were on CephFS
       without CTDB. They are local now, and every Samba machine sets the app
       passwords at boot and not only the lease holder (see the
       [design](./design.md#decisions)). smbd also needs the mounts of its
       shares now, which it got for free from the state on CephFS before.
     - The next run lost a file that smbd had confirmed: it was still in the
       CephFS cache of the killed machine. smbd now syncs every write first.
     - Two mounts with a new common parent raced in their pre-mount, and one of
       them failed: `mkdir -p` stops with `ObjectExists` when another mount
       makes a parent at the same time. The pre-mount now tries until the
       directory is there.
   - On 2026-11-26, the split and the freeze went into the same loop as the
     kill, `fault_each`, so every contract and `services-etcd` kill, split off
     and freeze each server once, in one test. A split drops everything between
     the server and the other servers with iptables, and the client still
     reaches both sides. A freeze stops every process of a container with
     SIGSTOP, or pauses a VM, for at least `toh.test.faults.freezeTime`. At the
     end, every value is checked again on the whole cluster. The kill option
     `toh.test.faults.kills` is now `amount`, the number of faults. What the
     splits and freezes found:
     - A machine that was split off still answered DNS for the services with
       only its own relay, so a client that asked it never reached the new
       primary. It now refuses those queries while it reaches fewer than half of
       the relays (see the [design](./design.md#decisions)), and
       `services-coredns-relays` checks it.
     - Later on 2026-11-26, every fault became a test of its own
       (`self.lib.test.faultTests`, then `<name>-kill`, `-split` and `-freeze`),
       because one test of all faults ran for over 30 minutes before it showed a
       failure. A failed test now prints what the processes of every server wait
       on, the journal of the units the test names and the output of the
       commands it names. The Valkey loss seen in the first split run went to
       the [to do](./todo.md), with how to look for it again.
     - OpenBao on the new active machine hung for minutes after a split: it
       opened database connections to the Envoy of the cut off machine, which
       drops them without an answer, so each one waited out the retries of the
       kernel. The URL of every database app now has a `connect_timeout`, the
       tunable `toh.services.patroni.connectTimeout`, 5 seconds by default, and
       `contracts-secrets-openbao-split` passes. Envoy also closes the open
       connections to a backend that fails its checks now, so a pool does not
       keep talking to an old primary; no run showed whether that was needed.
     - CephFS counted as redundant again while the monitor of a machine that had
       just come back was still joining, so splitting the next machine left no
       quorum. `redundant` for CephFS now also waits for every monitor to be in
       the quorum.
     - A machine that was split off for longer than a minute had its CephFS
       mounts evicted, and they kept failing after the split healed, so Samba
       never came back there. A watchdog now mounts an evicted mount again (see
       the [design](./design.md#decisions)), with the tunables
       `toh.services.cephfs.mountWatch.interval` and `timeout`.
     - After a heal, the init of a container sometimes hung for good, and every
       `systemctl` in it failed with "Transport endpoint is not connected". The
       test driver of nixos-26.05 stops reading the notify socket of a container
       once it booted, and the init blocks once that socket is full. nixpkgs
       master reads it for as long as the container runs, and
       `src/nix/test/notify.nix` does the same until that is in a release.
       `contracts-share-samba-split`, `contracts-filesystem-cephfs-split` and
       `contracts-oidc-authelia-split` pass.
     - `contracts-database-patroni-freeze` lost confirmed writes: when the
       machine that led both Patroni and etcd woke up, its etcd revoked the
       lease of the new Patroni leader, the old primary took the free leader
       key, and the others rewound onto its old timeline. etcd checks that it
       still leads before it revokes leases, but skips the check while its clock
       ticks, and a paused process ticks again at once. A patch to etcd always
       does the check now, and the test passes with it; the report to etcd is in
       the [to do](./todo.md).
     - `contracts-secrets-openbao-freeze` found no active OpenBao after a
       freeze. OpenBao kept a database connection through the relay of the
       frozen machine, whose kernel still acknowledged, so the connection hung
       for good while it held the state lock of the new active node. CoreDNS
       named every relay to the programs of a machine, its own first, and
       OpenBao had once fallen through to another one. Now a machine whose own
       relay answers gets only that one (see the
       [design](./design.md#decisions)).
     - `contracts-email-maddy-freeze` could not send mail while a Garage machine
       was frozen. A Garage read asks only as many nodes as its quorum needs,
       the fastest first, and the frozen node still had a fast ping, so the read
       waited for its RPC timeout of 30 seconds. Envoy ends a request that is
       quiet for 30 seconds, so the read never got to the next node.
       `toh.services.garage.rpcTimeout` is now 10 seconds.
     - `contracts-secrets-openbao-split` cut off the new primary of Patroni
       while the old one still rewound from it. The standby that took over had
       no replica left, and in strict synchronous mode it commits nothing then,
       so OpenBao never got its lock. The test had waited only for a synchronous
       standby; `redundant.patroni` now waits for every replica to stream.
     - On 2026-11-27, `contracts-git-forgejo-freeze` hung for over 30 minutes in
       the freeze of the last server, until its global timeout. A process that
       waits in the kernel, like on the CephFS mount whose FUSE daemon was
       already stopped, cannot stop until it leaves the kernel, and the freeze
       waited for it to. It now counts as stopped once it has its SIGSTOP, and a
       freeze fails after `toh.test.faults.freezeTimeout`, naming what still
       runs. The test passes in 8 minutes, and its fault tests get the 10
       minutes of step 8.3 already.
   - Done on 2026-11-27, with the kill, the split and the freeze, and the other
     faults moved to chunk 4 (see above). In the last sweep, every fault test
     passed except `contracts-kv-valkey-freeze`, which failed with six tests at
     a time and passed on its own.

2. **Test tiers (M).** Decided on 2026-11-27. On that day the suite had 91 tests
   and ran for about an hour with six at a time, and most of the work left does
   not touch the faults. So every test sets the required option `toh.test.tier`,
   which `dev test` reads from `passthru.tier`:
   - Tier 1: the happy path of a service or contract, kept fast. CI runs it on
     every change, as the check that nothing broke badly.
   - Tier 2: the faults of step 8.1, so every test that `faultTests` makes.
   - Tier 3: the VM tests. The tier replaces `passthru.skipped` and `--skipped`.

   Every test sets its tier by hand, VM tests too; it does not follow from
   `toh.test.kind`. `dev test --tier <n>` runs the tests of tier `n` and below,
   tier 1 by default. `--all <regex>` runs every tier of the tests whose names
   match, whatever `--tier` says. So work on one area runs, for example,
   `dev test --all cli` for all the tests of that area and tier 1 of the rest.
   Releases run `--tier 3`. Steps 9 to 11 tier their tests the same way. Done
   when every test sets a tier, `dev test` has both flags, CI runs tier 1, and
   `AGENTS.md` and the docs speak of tiers and not of skipped tests.

   What happened:
   - Done on 2026-11-27. `src/nix/test/tiers.nix` holds the option and puts it
     in `passthru.tier`, and every test sets it. `dev test` reads it, prints the
     tests it leaves out with their tier, and counts them as left out.
   - The contracts with faults and `services-etcd` had only their fault tests
     since every fault became a test of its own, so they had no tier 1 test.
     `faultTests` now also makes the test under the plain name, without faults,
     like `contracts-git-forgejo`.

3. **Test hardening (L).** Ensure each and every test has builtin retries and
   such so that it is not flaky. This is important because we want to be
   absolutely sure that what is being tested is the failure and not the test.
   Fill the behavior holes found in step 7 too, listed in
   [what the tests show](./behavior.md).

   Decided on 2026-11-27, every test also runs within a budget:
   - The global timeout of a test comes from its tier: 5 minutes for tier 1 and
     10 for tiers 2 and 3, and no longer from the sum of the worst cases of its
     faults. A test that needs more says why in a `NOTE`, and one that runs much
     faster may set less.
   - Everything a test waits on has a timeout well inside the budget, so a hang
     fails early and the report of the faults still runs.
   - `dev test` prints how long each test took, so a sweep shows which tests
     come close to their budget.
   - A fault test may shorten the timings of a service, like the graces of
     CephFS or the freeze time, to fit. The faults check that the cluster stays
     correct, and not how fast it is with the defaults.
   - Every fault still goes to every server, in one test per fault.

   What happened:
   - Started on 2026-11-27. `dev test` prints how long every test took, once it
     ends and again at the end, longest first, so a sweep shows where the time
     goes before the budgets are set.
   - The global timeout comes from the tier, through the tunable
     `toh.test.budgets`. The sum it replaced was the only use of
     `toh.test.faults.amount`, which is gone. The human chose not to measure the
     whole suite first, since one run takes most of a night: the sweep of the
     hardening finds the tests that run out of time, and they get fixed as it
     goes.
   - `services-alertmanager-matrix` ran out of its 5 minutes, and had failed
     with six tests at a time before. Every bridge logged in to Synapse on every
     start, also the ones before the chat had made its room, and all of them log
     in as the same user. Synapse lets an account log in 5 times at once and
     then about once every 5 minutes, so the bridges locked the user out. A
     bridge now looks up the alias of the room first, which needs no login, and
     logs in only once the room is there.
   - `services-cephfs` and `services-etcd` sometimes never came up, the flake
     parked as "A flake when containers start". Each time it was nscd: NixOS has
     resolvconf restart nscd whenever it writes `resolv.conf`, at boot that came
     while nscd was still starting, and in a container the second start
     sometimes failed to spawn. Every `toh-*-online` target needs nscd. In the
     test containers nscd now starts after resolvconf, so the restart finds it
     not running yet and leaves it alone. Tests that passed earlier in the sweep
     were not run again for it.
   - `contracts-git-forgejo-split` and `-freeze` ran out of time, for three
     reasons. On a new database every LLDAP creates its default groups at the
     first start, and the ones that lose the race exited and stayed down; LLDAP
     and its initialization now start again after a failure, and the
     initialization, which waits for LLDAP without an end, has a timeout. Maddy
     kept its secrets in its own runtime directory, which goes away whenever
     Maddy stops, so after a restart it could not start again, and Forgejo,
     which needs it, stayed down too; the file is now in the runtime directory
     of the unit that writes it. And every fault of CephFS waits out its graces,
     105 seconds, which three servers do not fit in 10 minutes; a test with
     faults now shortens them to 30 and 20, through `toh.test.faults.cephfs`.
   - The VM tests of tier 3 broke the invariant of the firewall: NixOS runs
     dhcpcd by default, which listens on port 68. The test network gives every
     machine a static address, so the VMs of the tests turn DHCP off, like the
     containers, which never ran it. With that, every test of the three tiers
     passed in the sweep.
   - Every wait of a test script has a timeout now. About 30 waits for a unit or
     an interface had none, and so the 15 minutes of the test driver, longer
     than any budget; they wait 120 seconds now. The `wait_for_shutdown` of a
     killed container comes after a loop with its own deadline, and stays. The
     one-shot units that start with `TimeoutStartSec = "infinity"`, the
     initializations of Forgejo, Garage, OpenBao and Patroni and the wait of
     chronyd, stay too: they start again after a failure and stop with their
     service, and a timeout there would only start them again, while the wait of
     the test on their target already has one.
   - The holes of [what the tests show](./behavior.md) are filled one service at
     a time, the checks that something is turned away first, from 2026-11-28.
     Backup and the CLI stay with step 9, OpenBao with its parked fixes, and
     NetworkManager with what a container cannot show. Filled: etcd turns away a
     client without a certificate; the stats port of Envoy closes the rest of
     its admin interface; the key of one S3 app cannot reach the bucket of
     another. For that one, Garage named the secrets of an app after the user
     that owns them, so two apps of one user clashed; they are named after the
     app now, which changes nothing while every app owns its secrets under its
     own name, as all of them do. The ACL of Valkey keeps an app to the keys and
     channels of its prefix, and refuses it the commands that flush every key,
     read the config or rewrite users. Those were open: apps got every command
     by default, so one could give itself every key. Now they get reading,
     writing, keyspace and connection commands by default, Synapse channels too,
     and every ACL user but those of Valkey itself is denied the dangerous ones.
     The ACL also keeps an app to its database now, which Valkey can since 9.1;
     before, Forgejo, Synapse and Authelia, which use a database of their own
     and no prefix, could reach the keys of each other. Channels have no
     database, so an app has a channel prefix apart from its key prefix, and
     Synapse keeps to the channels named after its server.

4. **More faults (L).** Moved from chunk 1 on 2026-11-27, with the same goal and
   the same rules for what holds after every fault:
   - Lose the majority: stop two machines. The last one refuses writes rather
     than serve alone, and the cluster comes back once a second machine does.
   - Restart in the wrong order: stop the whole cluster one machine at a time,
     then boot it one machine at a time, once with the machine that stopped
     first (and so has the oldest data) booting first and once with it booting
     last. No old data takes over.
   - Restart one machine after the other, like a deploy does. Writes work again
     after each one, before the next restarts.
   - Fail during recovery: kill a machine, bring it back, and kill another as
     soon as the tests call the cluster redundant again. This checks that
     `redundant` waits until the machine has caught up.

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
  from the nixpkgs container tests, and fix it here or in nixpkgs. The three
  seen on 2026-11-26 and 2026-11-27 were nscd, restarted by resolvconf while it
  started, fixed in step 8.3; the ones of 2026-11-18 have no logs left.
- **Simplify the services.** Much of the service code repeats itself. Move the
  shared parts into `self.lib`, with unit tests there, and keep the modules
  thin.
- **OpenBao fixes**, in a step not picked yet: TLS, keeping root material out of
  OpenBao, recovering from a failed init, the token timer, the shred, and the
  certificate check on the age key fetch.
- Modernizing cryl, which is its own project. Changes that ToH needs from cryl
  (like a fix for `config.flake.cyrl` in its flake module, which is misspelled
  on both `v0.4.1` and `main`) go there as issues.
