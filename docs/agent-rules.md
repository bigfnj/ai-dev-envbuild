# Agent Rules

Rules for any AI coding agent (Claude, Codex, Copilot, …) working in an
environment provisioned by this repo. Keep them; they prevent the duplication,
global-install rot, and rediscovery this environment exists to avoid.

## Before installing anything

1. **Check what's already here.** Run `devtools report` (full inventory) and
   `devtools check` (drift) before proposing or running any install. The
   environment is broad — the tool you want is probably already present.
2. The machine-readable source of truth is
   [`manifest/tools.json`](../manifest/tools.json). Each entry records the
   tool's binary, group, scope (global / project-local / container), install
   method, and a detect command.

## Python

- **`uv` for project dependencies and Python versions.** `uv venv`,
  `uv add`, `uv run`, `uv python install <ver>`. Every project gets its own
  `.venv`.
- **`pipx` for global Python CLIs only** (ruff, ipython, jupyterlab, …).
- **Never `pip install` into system Python.** Never `pipx` a library.
- `pytest`, `mypy`, and all libraries are **project-local** (`uv add --dev`),
  not global.

## Node / TypeScript

- **`pnpm` for project packages**; everything lives in local `node_modules`.
- Only `pnpm` and `tsx` are global (and via npm's user prefix `~/.local`).
- TypeScript, ESLint, Prettier, Vite, frameworks → **project-local**.

## Global vs project-local (the boundary)

- **Global** is for *tools you invoke by name* (rg, jq, ffmpeg, ruff). A library
  you `import`/`require` is **project-local**.
- **Heavy, risky, or version-pinned** work (ML/CUDA stacks, untrusted binaries,
  a client's exact toolchain) goes in a **container / devcontainer**, not the
  base system.
- Active project work lives under **`~/projects`** (Linux filesystem), never
  `/mnt/c`. See [`wsl-filesystem.md`](wsl-filesystem.md).

## When you do add a tool

Never install ad hoc and never hand-edit `manifest/tools.json` — the manifest is
*generated* by each module. Follow this so a re-run and other machines stay
consistent:

1. **Confirm it's missing:** `devtools report` / `devtools check`.
2. **Edit the right `modules/<group>.sh`** (add a whole new group only if none
   fits — see the README "Extending" section):
   - Install it in the group's `*_install`, guarded with `has`, via the correct
     channel: `apt_install <pkg>` (system) · `pipx_install <pkg>` (global Python
     CLI) · `npm_global <pkg>` (global Node CLI) · or a guarded download into
     `~/tools/bin`.
   - Record it in the group's `*_record_manifest`, guarded with `if has <bin>`:
     `manifest_add <name> <binary> <group> <scope> <install_method> "<detect>" <status> "<notes>"`.
     `scope` = `global` | `project-local` | `container`;
     `status` = `core` | `optional` | `experimental` | `isolated`;
     `detect` = a command that exits 0 when the tool works (usually
     `<bin> --version`; use `command -v <bin>` if it has no version flag).
3. **Apply it:** `./bootstrap.sh --only <group>` — installs the tool AND
   regenerates the manifest. Editing the module without running it leaves the
   manifest stale.
4. **Gate — both MUST pass before you push anything:**
   - `devtools check` — no manifest drift.
   - `smoke-test` — must exit 0. It exercises the toolchain end-to-end; a core
     failure means a broken build. Do not push a red smoke-test; fix it first.
5. **Only after step 4 is green, commit + push** so other workstations get it:
   `git add -A && git commit && git push`. Other machines pick it up with
   `git pull && ./bootstrap.sh`.

## Don't

- Don't append directories to `PATH` ad hoc. The only base additions are
  `~/.local/bin` and `~/tools/bin` (in `~/tools/shellrc.sh`); version managers
  manage their own (e.g. `~/.cargo/bin`).
- Don't install large optional stacks by default — `optional-heavy` and
  `optional-gpu` are explicit opt-in groups.
- Don't push a change without a green `smoke-test` — it's the build gate.
- Don't duplicate a tool that's already in the manifest under a different
  install method.
