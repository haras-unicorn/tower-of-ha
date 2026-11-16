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
S3, LDAP, single sign-on, email, git, passwords, files, secrets and, later, chat
and observability. It is free software from top to bottom.

The target hardware is a handful of Raspberry Pis. That is the yardstick for
memory, CPU and disk.

## Scope

**Decided.** ToH protects data from leaking **through the network**. The two
main defenses are the VPN and TLS on every connection, even inside the VPN.
Machines and admins that are part of the cluster get a base amount of trust.

**Decided.** Leaking data from a **physical device** (a stolen disk, a lost Pi)
is out of scope. The machines are planned to run on
[stolon](https://github.com/haras-unicorn/stolon), which covers that with an
encrypted disk, but stolon is not part of this repository.

**Decided.** Access control (ACL) means: which machines, users and services can
reach which other machines, users and services, no matter how they try (our CLI,
a service, or someone running `curl`). It should be done at the network level
and be as good as is reasonable, not perfect.

## Invariants

These hold for every change. **Proposed** as a set: please confirm, cut or add.
Where today's code breaks one, the [plan](./plan.md#where-it-stands) says so.

1. **Free software only.** No unfree package anywhere in the closure of a
   machine, a test or the CLI.
2. **Sops is the source of truth for secrets.** The sops files in the repository
   of each deployment hold every secret. Everything else (OpenBao, files on a
   machine) is a copy made from them. Nothing writes back. (**Decided**.)
3. **Least privilege for secrets.** The sops file of a machine holds only the
   secrets that machine uses.
4. **TLS on every hop.** Every connection between two processes is TLS, also
   inside the VPN and also behind the proxy.
5. **High availability or a written reason.** Every service runs on more than
   one machine, or has a documented failover, or says in its docs why it is a
   single instance.
6. **Tests test the real thing.** Tests use the same NixOS modules as a real
   deployment. Nothing that a machine needs to work is defined only in tests.
7. **Containers first.** Tests run as systemd-nspawn containers. A test runs as
   a VM only when containers cannot do it, and says why. (**Decided**.)
8. **Contracts, not implementations.** Each capability (VPN, DNS, proxy,
   database, ...) has tests that any implementation must pass. (**Decided** as
   step 2.)
9. **Cheap hardware.** A three-Pi cluster runs the default stack.
10. **No magic values.** Ports, timeouts and similar values are module options
    with defaults, as the coding style asks.

## Decisions

Made on 2026-11-16, when this plan was started.

- **Order of work.** Modernize and move to containers first, then make the tests
  independent of the services, then add chat and observability, then swap out
  Nebula and HAProxy, then harden, then the CLI, ACL and workflows. Details are
  in the [plan](./plan.md#order).
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
  reference. Synapse allows only one main process per homeserver, so it needs a
  failover design first (see [open questions](#open-questions)).

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
  HAProxy module fills this in for every service, with HAProxy's own port
  scheme.
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
test module `src/test/targets.nix`. A real machine would not have them.

### Secrets today

- Each module adds cryl generations to `toh.meta.cryl.cluster` (shared secrets,
  like the CA) and `toh.meta.cryl.machine` (per machine secrets, like a TLS
  leaf). A machine copies the cluster secrets it needs by name, so its sops file
  only holds what it uses.
- Each module declares the sops secrets it reads in `toh.meta.sops.secrets`.
- In tests, `src/test/secrets.nix` builds the cryl specifications, runs cryl and
  points sops-nix at the result. That is the only place where
  `toh.meta.sops.secrets` is passed to sops-nix.
- OpenBao, when enabled, does more than distribute. On the first machine it:
  initializes itself, stores its own root token and recovery keys in its own
  key-value store, creates a user for every machine, and uploads the whole
  decrypted sops file of that machine. Machines are then meant to fetch their
  age key from OpenBao at boot, or from an "offerer" on the local network, which
  does not exist in the code yet.

### Tests today

`pkgs.tohPackages.testers.runToHTest` wraps `runNixOSTest` with QEMU VMs of 8
GiB and 4 cores each, and test modules under `src/test/` for clusters, scripted
commands, a fake network, DNS, NTP, S3, HTTP and so on. The VPN tests
(`toh.test.mesh`, `toh.test.relay`) are already independent of the
implementation: they take a service name and a unit, and both EasyTier and
Nebula run them.

## Target architecture

### haraspkgs as the base

**Decided**, details **proposed**.

- `flake.nix` calls `haraspkgs.lib.makeFlake` over `./src/nix`.
- `toh.lib` becomes `self.lib` (read through `selfLib`), `toh.overlays` becomes
  `self.overlays` with the `tohPackages` namespace, and our own overlay graph
  code and its tests go away.
- The NixOS modules become `self.nixosModules` with `flake = true`, so a
  deployment can import them.
- Tests become `self.nixosTests` (containers). Unit tests become
  `self.unitTests`.
- The dev shell becomes a haraspkgs dev module, which generates `.gitignore`,
  `.gitattributes`, the workflows, `LICENSE.md` and `CODE_OF_CONDUCT.md`.
- Nushell scripts use `pkgs.harasPackages.writeNushellApplication` and get their
  values from `renderMustache`, as the Nix style asks.
- Option docs are generated into the mdbook with `mkOptionsDocs`.

haraspkgs container tests do not configure QEMU nodes. A test that has to stay a
VM needs another way. If that means going around haraspkgs, it gets a comment
and an issue for haraspkgs, per the Nix style.

### What a deployment looks like

**Proposed.** A deployment is its own flake, for example the one that will run
on the Pis. It imports a ToH flake module and describes the cluster once:

```nix
{
  toh.cluster = {
    domains.topLevel = "example.org";
    machines.pi1 = {
      system = "aarch64-linux";
      network.ip = "10.69.42.1";
      services.patroni.enable = true;
    };
  };
}
```

From that, the ToH flake module makes the `nixosConfigurations`, the cryl
specifications, the deploy targets and the cluster view every machine reads. The
tests build their clusters through the same module, so tests and real
deployments cannot drift apart (invariant 6).

### Secrets flow

**Decided**: sops in the deployment repository is the source of truth.
**Proposed**: how the pieces fit.

1. The deployment repository holds one sops file per machine, plus one cluster
   sops file with the shared secrets (the CA, cluster keys). The cluster file is
   encrypted to the admins' age keys. Each machine file is encrypted to that
   machine's age key and to the admins' keys, so an admin can always read and
   renew it.
2. The ToH CLI runs cryl. Before it generates anything, it makes the existing
   secrets available to cryl, so cryl only fills in what is missing and renews
   what is marked to renew. Without this step a second run would rotate every
   secret, the CA and the age keys included. How to do it is
   [open question 1](#open-questions).
3. cryl writes the sops files back into the repository. The admin reviews and
   commits them.
4. Machines get their sops file with their NixOS configuration and decrypt it
   with their own age key through sops-nix.
5. OpenBao, if enabled, gets a copy of what devices need to pull, pushed by the
   CLI from the sops files. Devices only read it. If OpenBao is lost, it is
   rebuilt from the sops files and nothing is gone.

### OpenBao

**Decided**: distribution only. **Open**: which devices pull from it, and what
they pull ([open question 4](#open-questions)). Whatever it serves, it serves
over TLS (invariant 4), and it does not keep anything that is not also in a sops
file (invariant 2). That includes its own recovery material.

### Network and ACL

**Decided**: EasyTier carries all traffic between machines and devices. ACL is
enforced at the network level.

**Proposed**: ACL rules are declared once, in the cluster description, as who
may reach what (for example "group `admins` may reach `ssh` on every machine",
"service `forgejo` may reach capability `database`"). A module turns them into
EasyTier ACL rules where EasyTier can express them, and into nftables rules on
each machine where it cannot. The proxy is not the only gate: a backend port is
closed to everything except the machines that should reach it.

### Capabilities and contracts

**Decided** as step 2. Each capability gets a test module, in the shape of the
VPN tests: it takes the implementation as a parameter and checks the behavior
any implementation must have. The `toh.meta` options for a capability say
nothing about the implementation. Today `toh.meta.proxies` carries HAProxy's
port scheme, and that has to move into the HAProxy module before Envoy can pass
the same tests.

### Tests

**Decided**: containers first. Running container tests needs these settings on
the machine that builds them (from the NixOS 26.05 manual):

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

From reading the code, these are also likely problems (not tried yet):

- the VPN needs a TUN device,
- chrony cannot set the clock,
- Ceph uses loop devices and FUSE,
- CTDB moves IP addresses with iptables.

The [plan](./plan.md#container-readiness) sorts every test by this.

## Open questions

Each has my recommendation first.

1. **How does cryl see existing secrets on a second run?** Today nothing imports
   them, so a real deployment would regenerate everything. cryl has no sops
   importer. Recommendation: the ToH CLI decrypts the sops files into cryl's
   working directory (in memory) and cryl imports them with its `copy` importer,
   so cryl needs no change. The alternative is a `sops` importer in cryl. Also
   needed either way: the sops files must be encrypted to the admin keys too
   (cryl's `sops` generator already takes several age recipients).
2. **Where does a machine's age key live?** Today it is meant to be fetched from
   OpenBao or a local "offerer" at every boot and shredded after. The offerer
   does not exist, and the fetch accepts any host on the LAN (`curl -k`).
   Recommendation: the CLI puts the key on the machine once, at install, into a
   folder that stolon keeps. It stays on the encrypted disk. This removes the
   whole boot-time fetch.
3. **What does a deployment flake look like?** Recommendation: the `toh.cluster`
   flake module sketched [above](#what-a-deployment-looks-like), built in step
   1, because the tests need it too.
4. **What is OpenBao for?** Which devices pull from it (friends' phones,
   machines that do not run NixOS, the CLI on a laptop) and what do they pull?
   If nothing needs it yet, we could keep it off by default until the step that
   needs it.
5. **How does Synapse fail over?** It allows one main process per homeserver.
   Recommendation: elect the main process the way Patroni elects a primary, with
   a lease in etcd, and run workers on every machine. To be designed in step 3.
6. **Is OpenSearch right for Raspberry Pis?** The README lists Fluentd and
   OpenSearch for observability. OpenSearch is a heavy Java service. To be
   decided in step 4, against invariant 9.
7. **Where do the `TODO` comments go?** The coding style says they become
   issues. Recommendation: GitHub issues on this repository, made once the plan
   is approved.
