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

1. Put it in the correct `modules/<group>.sh`, guarded with `has` so re-runs
   skip it.
2. Use the right channel: `apt_install` (system), `pipx_install` (global Python
   CLI), `npm_global` (global Node CLI), or a guarded download to `~/tools/bin`.
3. Add a `manifest_add` entry so `devtools` and the next agent can see it.
4. Run `devtools check` to confirm no drift.

## Don't

- Don't append directories to `PATH` ad hoc. The only base additions are
  `~/.local/bin` and `~/tools/bin` (in `~/tools/shellrc.sh`); version managers
  manage their own (e.g. `~/.cargo/bin`).
- Don't install large optional stacks by default — `optional-heavy` and
  `optional-gpu` are explicit opt-in groups.
- Don't duplicate a tool that's already in the manifest under a different
  install method.
