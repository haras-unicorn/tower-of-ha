# Design

This page says what Tower Of HA is meant to be, how it works today, and where it
is going. The [plan](./plan.md) says how we get there, step by step.

Every statement here is one of three kinds:

- **Decided**: agreed on, change it only on purpose.
- **Proposed**: my suggestion, waiting for a yes or no.
- **Open**: a question that has to be answered before the step that needs it.

## What Tower Of HA is

Tower Of HA (ToH) is a set of NixOS modules that turn a few cheap machines into
one highly available service stack: VPN, DNS, proxy, database, key-value store,
S3, LDAP, single sign-on, email, git, files, secrets and, later, chat and
observability. It is free software from top to bottom.

The target hardware is a handful of Raspberry Pis. That is the yardstick for
memory, CPU and disk.

## Scope

**Decided.** ToH protects data from leaking **through the network**. The two
main defenses are the VPN and TLS on every connection, even inside the VPN.
Machines and admins that are part of the cluster get a base amount of trust.

**Decided.** Leaking data from a **physical device** (a stolen disk, a lost Pi)
is out of scope. ToH is only the highly available service stack. Disks and other
physical concerns belong to whatever the machines run on.

**Decided.** Access control (ACL) means: which machines, users and services can
reach which other machines, users and services, no matter how they try (our CLI,
a service, or someone running `curl`). It should be as good as is reasonable,
not perfect. There are three levers, one per level:

- **EasyTier** for the network: who can reach which machine and port.
- **Envoy** for ports and applications: who can reach which service.
- **OpenBao** for secrets: who can read which secret.

## Invariants

These hold for every change. **Decided** on 2026-11-17. Where today's code
breaks one, the [plan](./plan.md#where-it-stands) says so.

1. **Free software only.** No unfree package anywhere in the closure of a
   machine, a test or the CLI.
2. **Sops is the source of truth for secrets.** The sops files in the repository
   of each deployment hold every secret. Everything else (OpenBao, files on a
   machine) is a copy made from them. Nothing writes back.
3. **Least privilege for secrets.** The sops file of a machine holds only the
   secrets that machine uses.
4. **TLS on every hop.** Every connection between two processes is TLS, also
   inside the VPN and also behind the proxy.
5. **High availability, no exceptions.** Every service runs on more than one
   machine. A service that allows only one active process at a time (like
   Synapse) gets failover through an etcd lease, and keeps its data in Patroni
   or Ceph.
6. **Tests test the real thing.** Tests use the same NixOS modules as a real
   deployment. Nothing that a machine needs to work is defined only in tests.
7. **Containers first.** Tests run as systemd-nspawn containers. A test runs as
   a VM only when containers cannot do it, and says why.
8. **Contracts, not implementations.** Each capability (VPN, DNS, proxy,
   database, ...) has tests that any implementation must pass.
9. **Cheap hardware.** A three-Pi cluster runs the default stack.
10. **No magic values.** Ports, timeouts and similar values are module options
    with defaults, as the coding style asks.

## Decisions

Made on 2026-11-16, when this plan was started.

- **Order of work.** Modernize first, then move the tests to containers and make
  them independent of the services, then add chat and observability, then swap
  out Nebula and HAProxy, then harden, then the CLI, ACL and workflows. Details
  are in the [plan](./plan.md#order).
- **haraspkgs is the base.** The flake, dev shell, overlays, tests and generated
  files all come from [haraspkgs](https://github.com/haras-unicorn/haraspkgs),
  as in the other repositories.
- **EasyTier is the VPN.** Nebula goes away. EasyTier has a broader community,
  better ACL and features, and is easier to set up on devices that do not run
  NixOS, which matters for friends who join.
- **Envoy replaces HAProxy.** HAProxy has an enterprise edition, so it is not
  fully free software.
- **Cryl manages secrets.** [cryl](https://github.com/haras-unicorn/cryl) should
  be enough for all secret needs. Where it is not, the change goes into cryl and
  is not worked around here.
- **OpenBao only distributes.** It is a server that other devices pull secrets
  from. It is never the source of truth.
- **The Synapse work restarts in step 3.** The `matrix` branch stays as a
  reference. Synapse allows only one main process per homeserver, so it gets
  failover through an etcd lease. Its data lives in Patroni and Ceph.

Made on 2026-11-17, after review.

- **ToH is a suite of NixOS modules.** That is the main way to use it, because
  NixOS modules are the most stable contract we can offer.
  `nixosModules.default` imports all of them, as haraspkgs does. Anything on
  top, like a flake wrapper, is an extra.
- **cryl renews only on request.** It regenerates a secret only when that secret
  has `renew = true`. That is enough for re-runs, and cryl needs no change for
  it.
- **The age key lives on the machine.** It is put there before the first boot,
  with guestfish or a similar tool. The fetch over the local network stays.
- **OpenBao serves the CLI** and holds the per-secret access rules (see
  [Scope](#scope)). Its current problems get fixed later, not in step 1.
- **One big pull request, no CI for now.** ToH is not meant to be used yet, so
  most steps land in one major pull request, and CI stays off until it is worth
  having.
- **`TODO` comments go into [todo.md](./todo.md)** for now, since most of them
  will be fixed in that pull request.

## Architecture today

This is how the code on `main` works, as read on 2026-11-16.

### Flake

`flake.nix` uses flake-parts and import-tree, so every `.nix` file under `src/`
is a flake-parts module. The flake exports:

- `overlays`: the composed overlays.
- `packages` and `apps`: the `toh` CLI.
- `checks`: the NixOS tests, the nix-unit tests and the lint check.
- `lib`: meant to be a public library, but always empty, because no value sets
  the `_tohFlakeLib` marker it filters on.

It does **not** export NixOS modules or any way to build a real machine. The
modules can only be used inside the tests today.

### Namespaces

- `toh.lib`: helpers, merged into one attribute set and passed around as
  `tohLib`. It is defined at the flake level and again inside every NixOS
  machine and every test, and some helpers read the NixOS config of the machine
  they run on.
- `toh.overlays`: overlays with dependencies, sorted into a graph. The flake,
  every machine and every module can add overlays, so each machine can end up
  with its own `pkgs.tohPackages`.
- `toh.meta`: what a machine knows about itself and the cluster.
- `toh.services.<name>.enable`: turns a service on.

haraspkgs now does the first two (`self.lib`, `self.overlays`) in a more general
way. It grew out of the same ideas.

### Machines and the cluster view

Every machine sets `toh.meta.machine` (name, index), `toh.meta.network` (VPN
address, interface, subnet) and so on. `toh.meta.cluster.machines` holds every
machine of the cluster, including the full NixOS config of each one. Modules use
it to find the machines that run a service, through helpers like
`tohLib.serviceMachines "patroni"`.

In tests the cluster comes from the test nodes (`tohLib.cluster.fromTestNodes`).
There is no equivalent for a real deployment yet.

### Services and capabilities

A service module turns on the NixOS service and declares what it offers:

- `toh.meta.services.<name>`: the endpoint (protocol, port) and health check.
- `toh.meta.proxies.<name>`: where clients reach it through the proxy. The
  `toh.meta.proxy` module works this out for every service, from
  `toh.meta.services` and the ports in `toh.meta.proxy.ports`, and the machines
  that set `toh.meta.proxy.enable` become `toh.meta.relays`. A proxy module only
  turns that flag on and serves what meta says.
- Capability options such as `toh.meta.database`, `toh.meta.kv`, `toh.meta.s3`,
  `toh.meta.ldap`, `toh.meta.oidc`, `toh.meta.email`, `toh.meta.git` and
  `toh.meta.filesystem`. A service that needs a database registers itself in
  `toh.meta.database.apps` and gets a user, a database and certificates, without
  knowing it is Patroni.

DNS (CoreDNS) answers every service name with the addresses of all proxy
machines.

### Readiness targets

Each capability has a systemd target, like `toh-database-online.target` or
`toh-kv-online.target`. The service that provides it binds the target to its
unit, and services that need it wait for the target. This keeps services from
knowing about each other.

The base definitions of these targets (what each one waits for) live only in the
test module `src/nix/test/targets.nix`. A real machine would not have them.

### Secrets today

- Each module adds cryl generations to `toh.meta.cryl.cluster` (shared secrets,
  like the CA) and `toh.meta.cryl.machine` (per machine secrets, like a TLS
  leaf). A machine copies the cluster secrets it needs by name, so its sops file
  only holds what it uses.
- Each module declares the sops secrets it reads in `toh.meta.sops.secrets`.
- In tests, `src/nix/test/secrets.nix` builds the cryl specifications, runs cryl
  and points sops-nix at the result. That is the only place where
  `toh.meta.sops.secrets` is passed to sops-nix.
- OpenBao, when enabled, does more than distribute. On the first machine it:
  initializes itself, stores its own root token and recovery keys in its own
  key-value store, creates a user for every machine, and uploads the whole
  decrypted sops file of that machine. Machines are then meant to fetch their
  age key from OpenBao at boot, or from an "offerer" on the local network, which
  does not exist in the code yet.

### Tests today

`pkgs.tohPackages.testers.runToHTest` wraps `runNixOSTest` with QEMU VMs of 8
GiB and 4 cores each, and test modules under `src/nix/test/` for clusters,
scripted commands, a fake network, DNS, NTP, S3, HTTP and so on. The VPN tests
(`toh.test.mesh`, `toh.test.relay`) are already independent of the
implementation: they take a service name and a unit, and both EasyTier and
Nebula run them.

## Target architecture

### haraspkgs as the base

**Decided**, details **proposed**.

- `flake.nix` calls `haraspkgs.lib.makeFlake` over `./src/nix`.
- `toh.lib` becomes `self.lib` (read through `selfLib`), `toh.overlays` becomes
  `self.overlays` with the `tohPackages` namespace, and our own overlay graph
  code and its tests go away. **Done** in step 1, with two differences:
  - The helpers that read the NixOS config of a machine are now plain functions
    that take that config, like
    `selfLib.cluster.serviceMachines config "patroni"`.
  - A NixOS option `toh.overlays` stays, because modules add CLI parts that
    depend on the machine config. It starts from the flake overlays and is
    composed with the graph helpers of haraspkgs.
- The NixOS modules become `self.nixosModules` with `flake = true`, so a
  deployment can import them. `nixosModules.default` imports all of them.
- Tests become `self.nixosTests` (containers). Unit tests become
  `self.unitTests`.
- The dev shell becomes a haraspkgs dev module, which generates `.gitignore`,
  `.gitattributes`, the workflows, `LICENSE.md` and `CODE_OF_CONDUCT.md`.
- Nushell scripts use `pkgs.harasPackages.writeNushellApplication` and get their
  values from `renderMustache`, as the Nix style asks.
- Option docs are generated into the mdbook with `mkOptionsDocs`.

haraspkgs container tests do not configure QEMU nodes. A test that has to stay a
VM needs another way. **Done** in step 2 without going around haraspkgs: every
test is a `self.nixosTests` entry made by `selfLib.test.makeNixosTest`, and
`toh.test.kind` puts all machines of a test, helper servers included, into
`containers` or `nodes`.

### What a deployment looks like

**Decided.** A deployment is a set of NixOS machines, usually in the user's own
flake. It has:

- **One shared module**, imported by every machine of the deployment. It imports
  `nixosModules.default` and sets the options that must be the same everywhere,
  like the domain.
- **One module per machine**, which sets what is specific to that machine and
  picks the services it runs.
- **The cluster view.** The user passes the configurations of all machines into
  `toh.meta.cluster.machines`, so each machine can see where every service runs.
  This is how it works today in the tests, and it stays.

A thin wrapper could later do the parts every ToH flake needs anyway, like
filling in the cluster view. That comes later and is an extra. The tests build
their clusters the same way a user would, so tests and real deployments cannot
drift apart (invariant 6).

### Secrets flow

**Decided**: sops in the deployment repository is the source of truth, and cryl
makes and renews the secrets.

1. The deployment repository holds one sops file per machine. Shared secrets,
   like the CA, are copied into a machine's file only if that machine uses them.
2. The ToH CLI runs cryl. cryl only makes secrets that are missing and renews
   the ones marked `renew = true`.
3. cryl writes the sops files back into the repository. The admin reviews and
   commits them.
4. Each machine has its own age key on disk, put there before the first boot. It
   decrypts its sops file with that key through sops-nix.
5. OpenBao gets a copy of what the CLI and other devices need to pull, made from
   the sops files. Devices only read it. If OpenBao is lost, it is rebuilt from
   the sops files and nothing is gone.

### OpenBao

**Decided**: OpenBao serves the CLI and holds the access rules per secret. It
never holds anything that is not also in a sops file (invariant 2), and it
serves over TLS (invariant 4). Today it breaks both, see the
[plan](./plan.md#security). That gets fixed later, not in step 1.

### Network and ACL

**Decided**: EasyTier carries all traffic between machines and devices, and the
ACL uses the three levers in [Scope](#scope).

**Proposed** for step 10: the rules are declared once, in the shared module, as
who may reach what (for example "group `admins` may reach `ssh` on every
machine", "service `forgejo` may reach capability `database`"). Modules turn
them into EasyTier rules, Envoy rules and OpenBao policies, and into nftables
rules on each machine where EasyTier cannot express them. The proxy is not the
only gate: a backend port is closed to everything except the machines that
should reach it.

### Capabilities and contracts

**Decided** as step 2. Each capability gets a test module, in the shape of the
VPN tests: it takes the implementation as a parameter and checks the behavior
any implementation must have. The `toh.meta` options for a capability say
nothing about the implementation. The proxy addresses moved out of the HAProxy
module into `toh.meta.proxy` on 2026-11-18, so Envoy can serve the same ones.

**Decided** on 2026-11-19: the shape of a contract.

- **One test module per capability**, `src/nix/test/contracts/<capability>.nix`,
  with its options under `toh.test.contracts.<capability>`.
- **The implementation is a tag.** `implementation` is an `attrTag`, so a test
  picks one implementation and could pass it options. The tags come from an
  internal option, `implementationModules`, an `attrsOf deferredModule` with one
  submodule of options per implementation. The contract does not know any
  implementation.
- **An implementation plugs itself in** with a test module next to its service,
  in its `test.nix`. That module adds its tag to `implementationModules`, and
  when a test picks that tag, sets up the servers: its own service and whatever
  it depends on. For now every implementation submodule is empty, because every
  option there would need its own tests.
- **A separate client** checks the capability. It runs nothing of the
  implementation and knows only `toh.meta.*`: it registers an app, gets its
  connection details back, connects and uses the capability. It does not wait on
  readiness targets or units, only on the connection working. Names resolve
  through the DNS helper server of the tests, so the client does not depend on
  the DNS implementation either.
- **Happy path first.** A contract checks that the capability works. Losing a
  machine and other unhappy paths come in later contracts, and the nasty faults
  in [step 8](./plan.md#step-8-chaos-engineering).
- **Implementation tests stay** for what only that implementation has, like
  `patronictl list`. A contract chunk drops the service tests that its contract
  now covers.

With Patroni, the database contract looks like this:

```nix
# src/nix/modules/patroni/test.nix
self.lib.test.testModules.contracts-database-patroni =
  selfLib.test.contract.implementation {
    capability = "database";
    implementation = "patroni";
    server = {
      toh.services.etcd.enable = true;
      toh.services.coredns.enable = true;
      toh.services.haproxy.enable = true;
      toh.services.patroni.enable = true;
    };
  };

self.nixosTests.contracts-database-patroni = selfLib.test.makeNixosTest {
  toh.test.contracts.database = {
    enable = true;
    implementation.patroni = { };
  };
};
```

`server` is an internal `deferredModule` that the contract imports on each of
its servers, so the contract keeps the names and number of its machines to
itself. `selfLib.test.contract` (`src/nix/test/contract.nix`) holds what every
contract shares: the options above, the servers and DNS names (`base`), and the
test module an implementation plugs in with (`implementation`). An
implementation that needs more from the test, like a helper server, passes it as
`test`.

Writing this down showed a leak that the client will hit. Patroni makes the
credentials of an app only on machines that run Patroni, so an app on any other
machine cannot be registered at all: its `toh.meta.database.instances` entry
points at a Patroni user that does not exist there. Valkey looks the same, and
Garage already makes them on every machine that registers an app. Each contract
chunk checks and fixes this for its own capability.

### Tests

**Decided**: containers first, starting in step 2. Step 1 leaves the tests
alone, and they may stop working while the modules are ported. Running container
tests needs these settings on the machine that builds them (from the NixOS 26.05
manual):

```nix
{
  nix.settings = {
    auto-allocate-uids = true;
    extra-system-features = [ "uid-range" ];
    experimental-features = [
      "auto-allocate-uids"
      "cgroups"
    ];
  };
}
```

Containers share the host kernel. By the NixOS manual, they cannot:

- load kernel modules,
- run setuid binaries or switch to a specialisation,
- use many of systemd's sandboxing options such as `ProtectSystem=`.

What the tests ran into, and how they get around it:

- the VPN needs a TUN device,
- chrony cannot set the clock, so it runs with `-x`, and an optional VM test
  sets the real clock,
- Ceph cannot make loop devices, so OSDs keep their data in a plain file,
- `ceph-fuse` needs `/dev/fuse`, which the host passes into the build sandbox
  with `extra-sandbox-paths`.

The [plan](./plan.md#container-readiness) sorts every test by this.

## Open questions

None of these block step 1.

1. **Which observability stack?** It has to be light enough for Raspberry Pis
   (invariant 9). The README lists Fluentd and OpenSearch, and OpenSearch is a
   heavy Java service. To be decided in step 4.
2. **How do the Synapse workers fit the failover?** The main process fails over
   through an etcd lease. Whether workers run on every machine is to be decided
   in step 3.
