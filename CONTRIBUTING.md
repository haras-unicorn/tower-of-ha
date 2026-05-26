# Contributing to Tower Of HA

## Prerequisites

You need the [Nix](https://nixos.org) package manager (with flakes enabled).

## Getting started

```bash
git clone <repo-url>
cd tower-of-ha
nix develop .
```

Entering the dev shell makes the `dev-toh` command available. Run
`dev-toh --help` (or just `dev-toh`) to see all subcommands.

## Repository layout

Source code lives in `src/`. The project uses
[flake-parts](https://github.com/hercules-ci/flake-parts) and
[import-tree](https://github.com/denful/import-tree), so every `.nix` file under
`src/` becomes a flake-parts module.

- `src/lib/` — shared library functions.
- `src/meta/` — metadata schema (machines, network, domains, etc.).
- `src/modules/` — service implementations.
- `src/cli/` & `src/modules/cli/` — CLI tooling written in Nushell.
- `src/dev/` — dev-shell and test-runner definitions.
- `src/overlays/` — Nix overlays.
- `src/test/` — shared test helpers.
- `docs/` — mdbook documentation.

## Development workflow

1. Create a branch for your change.
2. Make edits.
3. Run tests and lint:

   ```bash
   dev-toh lint
   dev-toh test
   ```

   NixOS tests can also be run individually:

   ```bash
   dev-toh test nixos <test-name>
   ```

4. Update documentation if your change affects user-facing behavior.
5. Commit and push.

## Commit conventions

We follow [Conventional Commits](https://www.conventionalcommits.org/).

- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation only
- `test:` — adding or correcting tests
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `chore:` — tooling, dependencies, or other non-source changes

Keep the summary line concise (<= 72 characters).

## Pull requests

Pull requests should use the provided template and complete the checklist:

- [ ] I have read CONTRIBUTING.md
- [ ] I wrote/modified applicable tests
- [ ] I wrote/modified applicable documentation

CI runs on every PR:

- `check` — linting via `dev-toh lint`.
- The `nix flake check` step is currently disabled while some tests are being
  migrated.

## Documentation

Documentation is built with [mdbook](https://rust-lang.github.io/mdBook/).

```bash
nix build .#docs
```

The `docs` workflow publishes the book to GitHub Pages on every push to `main`.

## Release process

Releases are automated with
[Release Please](https://github.com/googleapis/release-please). Configuration
lives in `.release-please-config.json`. Do not bump `VERSION.txt` manually.

## Getting help

Open an issue or start a discussion in the repository. Use the issue templates
for bug reports and feature requests.
