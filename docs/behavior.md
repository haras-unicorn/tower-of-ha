# What the tests show

This page lists, per service, what its tests show that it does, beyond its units
running. It was written on 2026-11-24 in step 7 of the [plan](./plan.md), from
reading every test.

Each service has three parts:

- **Shows:** what the tests check that the service does.
- **Holes:** behavior that no test checks yet. Step 8.3 fills these.
- **Failover:** whether a test stops a copy of the service and checks that the
  others take over. Where none does, the faults of step 8.1 cover it. High
  availability means both failover and distribution: when one machine goes down,
  the service still answers and still has the same data.

Every test also runs the invariant checks (`src/nix/test/invariants.nix`), so
they are not repeated here. A contract test is listed under the service that
implements the contract.

## In short

- Every test has a tier. Tier 1 checks the happy path and runs on every change,
  tier 2 holds the fault tests, and tier 3 the VM tests, which both run before a
  release.
- Since step 8, every service that holds data has a fault test per fault, named
  after its test with `-kill`, `-split` or `-freeze` at the end. Each one hits
  every server in turn: it kills the machine, cuts it off from the others, or
  stops it like in a long pause. Then it checks that the service still answers
  and that what was written is still there. Where a service below says that its
  test kills every server once, the split and the freeze do the same with their
  fault. DNS, time, Prometheus and Alertmanager are left out on purpose.
- The weakest tests only show that units start: geoclue, NetworkManager, the
  Forgejo runner, and OpenBao beyond its contract. Backup has no test at all.
- `services-patroni-init` runs the same script as `services-patroni`, so it
  checks nothing about the init of its own.
- Most holes are a second step of a contract: a login after the OIDC discovery,
  git over SSH next to HTTPS, an app that may not read what another app wrote.

## Alertmanager

Tests: `contracts-alerts-alertmanager`, `services-alertmanager-matrix`.

- **Shows:** an alert that every copy of Prometheus fires is held once by the
  alerts API. An alert arrives as a message in the room of the `alerts` chat
  app.
- **Holes:** the invite of `toh.services.alertmanager.matrix.invite`, which the
  plan already names.
- **Failover:** none. Nothing checks that an alert is still sent once after one
  copy stops.

## Authelia

Tests: `contracts-oidc-authelia`, `services-authelia`.

- **Shows:** the discovery document names its issuer, a registered client with
  its secret can push an authorization request, and with a wrong secret it is
  turned away. The health endpoint answers through the proxy on every machine. A
  user from LLDAP logs in through Authelia's own API on one machine, and the
  session holds on every machine; a wrong password is turned away.
- **Holes:** none. The login is Authelia's API and not a browser, so the OIDC
  login of an app, with its redirect and consent, is not run.
- **Failover:** since step 8, the OIDC contract kills every server once, and the
  client still pushes its authorization request each time.

## Backup

No test. The module says it is incomplete.

- **Holes:** all of it. Step 9 writes the backup and restore commands, and step
  11 tests a restore.

## CephFS

Tests: `contracts-filesystem-cephfs`, `services-cephfs`,
`services-cephfs-mount`, and the VM test `services-cephfs-kernel-mount`.

- **Shows:** the cluster is healthy apart from clock skew. A file written on one
  machine is read on every other, through the FUSE mount, and through the kernel
  mount in the VM test. In the contract, a second client reads what the first
  wrote.
- **Holes:** none beyond failover.
- **Failover:** since step 8, the filesystem contract kills every server once,
  after every placement group is clean and a metadata server stands by. What the
  clients wrote before and after each kill is still there. When the active
  metadata server dies, that takes up to about two minutes (see the
  [design](./design.md#decisions)), and the test waits for it.

## chronyd

Tests: `contracts-time-chronyd`, `services-chronyd`, and the VM test
`services-chronyd-clock`.

- **Shows:** every serving machine answers over NTP. `toh-time-synchronized` and
  a service that depends on it go down and come back when chronyd is stopped,
  gets SIGTERM, or gets SIGKILL. In the VM, a clock that is off by an hour is
  set right.
- **Holes:** none.
- **Failover:** none across machines, only the restarts above.

## CLI

Test: `services-cli`.

- **Shows:** `toh` runs. Other tests use its commands: `toh ldap`, `toh s3`,
  `toh psql`, `toh valkey`, `toh ssh` and `toh email`.
- **Holes:** left to step 9, which rewrites the CLI.

## CoreDNS

Tests: `contracts-dns-coredns`, `services-coredns`, `services-coredns-relays`.

- **Shows:** it answers the node name of a machine with its address, without
  `/etc/hosts`. It forwards a zone it does not own to the server above it. Every
  other test resolves service names like `*.service.toh` through it. Service
  names point only at relays whose Envoy is ready, and a machine gets its own
  relay as `127.0.0.1`, which no other machine gets.
- **Holes:** none.
- **Failover:** not a goal of step 8. `services-coredns-relays` kills a relay
  and checks that its address leaves the answers and comes back after a revive.

## ddns-updater

Tests: `services-ddns-updater-duckdns`, `services-ddns-updater-cloudflare`.

- **Shows:** it gets the public address from a fake IP service and sends it,
  with the domain, to a fake DuckDNS or Cloudflare API, and when the address
  changes it sends the new one.
- **Holes:** none.

## EasyTier

Tests: `contracts-vpn-easytier-mesh`, `contracts-vpn-easytier-relay-proxy`,
`contracts-vpn-easytier-relay-punch`.

- **Shows:** five machines on one network reach each other over the VPN. Two
  homes behind NAT reach each other through a relay. With hole punching, the
  traffic goes straight between the homes and keeps going after the relay is cut
  off.
- **Holes:** none.

## Element

Test: `services-element`.

- **Shows:** every machine serves the page through the proxy, and its config
  names the chat and turns off integrations.
- **Holes:** none. It is static files.

## Envoy

Tests: `contracts-proxy-envoy` and its ten `balancing` variants.

- **Shows:** it routes by host, also with a port in the host header, by path
  prefix, by a regular expression that must match the whole path, and by
  priority. It spreads requests over every backend, leaves out a stopped one and
  takes it back, for HTTP, HTTPS and TCP with TLS ended, ended and started
  again, or passed through, and with every kind of health check.
  `services-prometheus` reads its stats on every machine. The stats port serves
  only the stats: the paths of the admin interface behind it that read the
  config or change and stop the proxy are closed to other machines.
- **Holes:** none.
- **Failover:** the balancing variants stop backends, not Envoy itself.

## etcd

Test: `services-etcd`.

- **Shows:** the health endpoint answers over TLS with a client certificate, and
  turns away a client without one. All three members are started. The Samba and
  Synapse tests use its leases (`toh.leases`) and move the holder.
- **Holes:** none.
- **Failover:** since step 8, `services-etcd` kills each member once. A key one
  member writes is read on another, before and after each kill.

## Falco

Tests: `services-falco`, and the VM test `services-falco-alerts`.

- **Shows:** its metrics can be read over the network. In the VM, reading
  `/etc/shadow` becomes an alert in Alertmanager.
- **Holes:** none that a container can show.

## Forgejo

Tests: `contracts-git-forgejo`, `services-forgejo`.

- **Shows:** an app makes a repository by pushing to it over HTTPS with its
  password, and clones it back. `services-forgejo` only waits for
  `toh-git-online` on every machine, with the runner on.
- **Holes:**
  - git over SSH, which Forgejo serves behind the proxy too,
  - a login through Authelia,
  - the runner registering and running a job.
- **Failover:** none.

## Garage

Tests: `contracts-s3-garage`, `services-garage`.

- **Shows:** an app puts and gets an object with its own key, and the key of a
  second app can neither read, write nor list its bucket, nor the other way
  round. Each machine puts an object, and every machine gets all of them.
- **Holes:** none.
- **Failover:** since step 8, the S3 contract kills every server once. Every
  object put before and after each kill can still be got.

## geoclue

Test: `services-geoclue`.

- **Shows:** its units start, and the static location from its secret is in
  `/etc/geolocation`, readable by geoclue.
- **Holes:** it answers a client with that location. In a container the client
  never gets an answer from geoclue over D-Bus, so this needs a VM test.

## journald

Test: `services-journald`.

- **Shows:** the size and age limits are in its config.
- **Holes:** none. The limits are all the module sets.

## LLDAP

Tests: `contracts-ldap-lldap`, `services-lldap`.

- **Shows:** an app binds with its own name and password and finds itself. The
  health endpoint answers, the admin finds itself, and a user added on any
  machine is found from every machine. An app with read-only permission is
  refused the password of the admin and adding a user, the only changes LLDAP
  takes over LDAP.
- **Holes:** none. LLDAP lets every user change their own password, so an app
  may too; the test does not try it, since the app binds with it.
- **Failover:** since step 8, the LDAP contract kills every server once. The app
  still binds and finds itself each time.

## Maddy

Tests: `contracts-email-maddy`, `services-maddy`.

- **Shows:** an app sends a mail to itself over submission with TLS and finds it
  over IMAP, and sends one to another app, which finds it in its own inbox. An
  app that sends as another app is refused. `services-maddy` lists the envelopes
  with the CLI.
- **Holes:** none.
- **Failover:** since step 8, the email contract kills every server once. Every
  mail sent before and after each kill is found over IMAP.

## NetworkManager

Test: `services-networkmanager`.

- **Shows:** only that NetworkManager and nftables are enabled.
- **Holes:** anything it does. A container may not be able to show more.

## node exporter

No test of its own. `services-prometheus` counts every machine in its `node`
job.

- **Holes:** its alerts (a disk or memory almost full, a failed unit) never fire
  in a test.

## OpenBao

Tests: `contracts-secrets-openbao`, `services-openbao`.

- **Shows:** with the token its machine fetched, the `bao` CLI writes and reads
  the secret of that machine through the proxy. `services-openbao` checks that
  the units run and that the first token fetch did not fail.
- **Holes:**
  - the token refresh, which would catch the timer bug in the plan,
  - a machine cannot read the secret of another,
  - OpenBao comes back after a restart.

  These go with the [parked](./plan.md#parked) OpenBao fixes.

- **Failover:** since step 8, the secrets contract kills every server once.
  Every secret written before and after each kill can still be read.

## OpenSSH

Tests: `services-openssh`, `services-openssh-cli-command`,
`services-openssh-cli-copy`.

- **Shows:** sshd is enabled without root, password or keyboard-interactive
  login, and a client that offers no key is turned away with only publickey
  left. `toh ssh command` and `toh ssh copy` work between two machines.
- **Holes:** none. Until now the test defaults turned on root and password
  login, a leftover of a debugging backdoor that is gone, so every test now runs
  sshd with the settings of the module.

## Patroni

Tests: `contracts-database-patroni`, `services-patroni`,
`services-patroni-init`, `services-patroni-cli`.

- **Shows:** an app connects over TLS with full verification and its own
  certificate, finds the table its init script made, writes a row and reads it
  back, and gets the locale it asked for. The health endpoint answers through
  the proxy, `patronictl list` works, and `toh psql` reads the table of inits.
- **Holes:** `services-patroni-init` checks the same as `services-patroni`.
- **Failover:** since step 8, the database contract kills every server once, the
  primary among them. Every write the app had confirmed is still there, and the
  app writes again through the proxy. The killed server comes back.

## PKI

Test: `pki`.

- **Shows:** the certificate folder is not empty.
- **Holes:** none in practice. Every TLS client of every other test needs the
  ToH CA in the bundle.

## Prometheus

Tests: `contracts-metrics-prometheus`, `services-prometheus`.

- **Shows:** a metric of a machine that runs no collector comes back at the
  query address. Every machine is counted once in every job (`node`, `envoy`,
  `prometheus`, `thanos-query`).
- **Holes:** none.
- **Failover:** yes. The count stays right after one copy stops.

## Samba

Tests: `contracts-share-samba`, `services-samba`.

- **Shows:** what an app writes, a second client reads. A file put through the
  proxy turns up in the CephFS mount of every machine. A user share can be
  added. Only one smbd runs at a time.
- **Holes:** none.
- **Failover:** when the holder of the lease stops cleanly, another machine
  starts smbd and serves the share. Since step 8, the share contract kills every
  server once, and the second client reads every file put before and after each
  kill. When the machine of smbd is killed, the next smbd waits for CephFS to
  free the dead machine's mount, about a minute.

## SSSD

Test: `services-sssd`.

- **Shows:** a user added to LLDAP on any machine is a system user on every
  machine (`getent` and `id`). PAM through SSSD lets that user in with the LLDAP
  password and turns away a wrong one.
- **Holes:** none past the login itself; the test uses a PAM service of its own,
  because the login service of a test container lets root in without asking.

## Synapse

Tests: `contracts-chat-synapse`, `services-synapse`,
`services-synapse-federation`.

- **Shows:** an app writes a message and a second client reads it. The main
  process uses Redis, and its replication listener answers through the proxy.
  Workers answer client and federation requests, and the main process does not.
  A user of the cluster and a user of an outside server read each other in one
  room, and the server well-known file names the cluster.
- **Holes:** uploaded media is still there after a failover, which is why the
  media store is on CephFS. Federation after a failover, which needs the same
  signing key on every machine.
- **Failover:** yes. When the holder of the lease stops, the main process moves,
  and Redis, replication and the workers work again.

## Valkey

Tests: `contracts-kv-valkey`, `services-valkey`.

- **Shows:** an app sets and gets a key under its prefix, over TLS with its own
  certificate and user. The CLI pings it on every machine, and every machine is
  either the primary with a replica or a replica that follows it. The ACL keeps
  an app to its database and to the keys and channels of its prefix, and refuses
  it the commands that flush every key, read the config or rewrite users.
- **Holes:** none. Synapse uses no key prefix, but its channels, which have no
  database, are kept to the ones named after its server.
- **Failover:** since step 8, the kv contract kills every server once, the
  primary among them. Sentinel picks a new primary, a server that comes back
  follows it, and every key the app wrote is still there. The app writes
  plainly, like the apps do, and the kill comes only after the lag of
  `toh.services.valkey.replicaMaxLag`: Valkey replicates after it answers, so
  the writes of the last seconds before the primary died can be lost (see the
  [design](./design.md#decisions)). Forgejo, Synapse and Authelia can lose that
  much of their cache, sessions, queue and worker messages.
