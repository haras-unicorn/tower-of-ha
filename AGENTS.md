# AGENTS.md

## Recreating this file

If you are asked to "recreate AGENTS.md", "improve AGENTS.md", or similar,
follow the same process used to produce this file originally:

1. Read as much of the codebase as possible to understand the current structure,
   conventions, and patterns.
2. Draft an outline for both AGENTS.md (agent instructions) and CONTRIBUTING.md
   (human instructions). They should cover similar topics but for different
   audiences: AGENTS.md must be strict, structural, and convention-heavy;
   CONTRIBUTING.md must be process-oriented (clone, dev shell, commits, PRs,
   CI).
3. Ask the user clarifying questions about anything you cannot infer from the
   repository alone.
4. Write or update the files based on the answers and your analysis.

AGENTS.md is strictly for AI agents. CONTRIBUTING.md is for human contributors.
Keep them separate and do not duplicate human process details into AGENTS.md.

---

## Repository overview

Tower Of HA is a highly opinionated, free and highly available NixOS service
stack. It is structured as a Nix flake built with
[haraspkgs](https://github.com/haras-unicorn/haraspkgs): `flake.nix` calls
`haraspkgs.lib.makeFlake` over `src/nix`, so every `.nix` file under `src/nix/`
is a flake-parts module.

Everything lives under the `toh` namespace:

- `toh.lib` — library functions and types.
- `toh.meta` — cluster metadata and declarative service wiring.
- `toh.services.<name>` — feature flags for individual services.
- `toh.meta.cryl` — secret generation configuration (never mutate secrets
  manually; use `cryl` generators).

## Directory layout

| Directory           | Purpose                                      |
| ------------------- | -------------------------------------------- |
| `src/nix/`          | All Nix code (flake-parts modules).          |
| `src/nix/lib/`      | Pure library functions and type defs.        |
| `src/nix/meta/`     | NixOS modules that define `toh.meta.*` opts. |
| `src/nix/modules/`  | NixOS modules that implement services.       |
| `src/nix/cli/`      | Base CLI scripts and package defs (Nushell). |
| `src/nix/dev/`      | Dev shell (a haraspkgs dev module), tooling. |
| `src/nix/overlays/` | Nix overlays and overlay utilities.          |
| `src/nix/test/`     | Shared NixOS test helpers and test modules.  |
| `docs/`             | mdbook documentation source.                 |

## Core conventions

### Attribute naming

- Service modules export `toh.lib.nixosModules.services-<name>`.
- Single-purpose modules export `toh.lib.nixosModules.<purpose>`.
- Overlays export `toh.overlays.<name>`.
- Internal/test modules export `toh.lib.test.nixosModules.*` or
  `toh.lib.test.testModules.*`.

### Options

- Use `lib.mkEnableOption` for boolean feature toggles.
- Use `lib.mkOption` with explicit types. Prefer `lib.types.submodule` for
  structured data.
- Service endpoints **must** be declared via `toh.meta.services.<name>` using
  `tohLib.services.endpoint` helpers. Do not hard-code hostnames or ports in
  service configs.
- Secrets **must** be declared via `toh.meta.cryl.machine` and
  `toh.meta.cryl.cluster` generators. Do not embed raw secret strings in Nix
  expressions.
- Use `lib.mkIf cfg.enable` to guard all config produced by a module.
- Use `lib.mkMerge` to combine multiple conditional configuration blocks.
- Use `lib.mkBefore` / `lib.mkAfter` when ordering matters inside lists.

### `tohLib`

`tohLib` is available as a module argument (`_module.args.tohLib`) and is the
merged contents of `config.toh.lib`. Use it for helper functions (e.g.
`tohLib.services.endpoint.toAttrs`, `tohLib.strings.indentTail`,
`tohLib.overlay.composeOverlay`).

### Overlays

All overlays are declared in `toh.overlays.*` and wired together by
`src/nix/overlays/default.nix` and `src/nix/overlays/nixos.nix`. They support explicit
dependency lists (`deps`) and regex-style matching. Cycles are rejected at eval
time.

## Adding a new service

1. Create `src/nix/modules/<service>/default.nix`.
2. Define `toh.lib.nixosModules.services-<service>`.
3. Add `toh.services.<service>.enable = lib.mkEnableOption "..."`.
4. Implement the service config inside `lib.mkIf cfg.enable { ... }`.
5. Register endpoints in `toh.meta.services.<service>` with protocol, port, and
   health checks.
6. If the service needs secrets, add `toh.meta.cryl.machine` and/or
   `toh.meta.cryl.cluster` generators.
7. Create `src/nix/modules/<service>/test.nix` with NixOS tests using
   `pkgs.tohPackages.testers.runToHTest`.
8. If the service exposes CLI commands, add Nushell scripts under
   `src/nix/modules/<service>/cli.nu` or similar and wire them via
   `tohLib.cli.makeOverlay`.

## Testing

- Unit tests: `dev test unit <filter>` (runs `nix-unit --flake .#tests`).
- NixOS integration tests: `nix flake check` or `dev test nixos <test-name>`
- Only use the built-in CLI wrappers for these tasks:
  - `dev check` — run all checks (spelling, markdown, `nil`, generated files).
  - `dev test` — run all tests.
  - `dev format` — auto-format the repository.

Do **not** run tools directly (e.g. do not invoke `prettier` or `nixfmt`
manually) unless you are fixing a bug in the wrapper itself.

## Linting & formatting

The development shell provides `dev`. The only commands an agent should use for
quality assurance are:

```bash
dev format   # auto-format everything
dev check    # check spelling, markdown style, nil and generated files
dev test     # run nix-unit and NixOS tests
```

## Guardrails

- **Never** modify `flake.lock` by hand. Use `nix flake update` or let the
  automated update workflow handle it.
- **Never** commit secrets, keys, or plain-text passwords.
- **Never** edit generated files (e.g. files produced by
  `renderMustacheTemplate`, build outputs in `result*`, ephemeral files). The dev
  shell generates `.gitignore`, `.gitattributes`, `.editorconfig`, `.envrc`,
  `LICENSE.md`, `CODE_OF_CONDUCT.md` and `.github/workflows/*`; edit
  `src/nix/dev/default.nix` instead.
- **Never** create, modify, or delete files outside the repository.
- **Never** use `/tmp`, `$TMPDIR`, or any external scratch space to store
  repo-related state unless a specific test or build step requires it.
- **Never** touch `.env` or `VERSION.txt` unless explicitly asked.
- **Never** assume a library is available without checking the flake inputs,
  overlays, or existing imports first.
- **Never** wrap commands in `nix develop .` and always assume you are already
  inside of the development shell
