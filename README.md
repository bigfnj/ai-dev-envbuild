# wsl-dev-envbuild

Reproducible, idempotent, agent-discoverable **WSL2 Debian development
environment** — a broad "Swiss army knife" workstation (modern dev, legacy
modernization, reverse engineering, image/media, office/PDF, data science, web
research) provisioned from one command.

```bash
git clone git@github.com:bigfnj/wsl-dev-envbuild.git
cd wsl-dev-envbuild
./bootstrap.sh
```

That's it. Re-run any time — it's idempotent.

## Design in one paragraph

Every tool has exactly one owner: **apt** (system CLIs, compilers), **version
managers** (language runtimes), **pipx** (global Python CLIs), **uv / pnpm**
(project libraries), and **containers** (heavy or risky stacks). Nothing is
installed two ways; the global vs project-local boundary is explicit; and a
machine-readable manifest plus a `devtools` command let a human or AI agent see
what's installed before touching anything. Full rationale:
[`docs/architecture.md`](docs/architecture.md).

## Install groups

`bootstrap.sh` runs groups in dependency order. Defaults run automatically;
`optional-*` need an explicit flag.

| Group | Default | Installs |
|---|:---:|---|
| `core` | ✅ | git, build toolchain, ripgrep/fd/fzf/bat/jq/delta, tmux, shellcheck, … (+ folders, PATH, `devtools`) |
| `python` | ✅ | pipx, uv (also Python versions), ruff, ipython, jupyterlab |
| `node` | ✅ | Node.js (NodeSource), pnpm, tsx |
| `languages` | ✅ | Rust (rustup), Go, OpenJDK + Maven, .NET |
| `reverse` | ✅ | radare2, binwalk, exiftool, tshark, foremost, **headless DOSBox-X**, frida, **Ghidra** |
| `data` | ✅ | DuckDB CLI, sqlite-utils, csvkit |
| `docs` | ✅ | pandoc, markdownlint-cli |
| `image` | ✅ | ImageMagick, ffmpeg |
| `containers` | ✅ | Docker Engine + Compose, devcontainer CLI |
| `optional-heavy` | ⛔ flag | QEMU |
| `optional-gpu` | ⛔ flag | NVIDIA/CUDA detection + guidance |

```bash
./bootstrap.sh                      # all default groups
./bootstrap.sh --only core,python   # just these
./bootstrap.sh --with optional-gpu  # defaults + a flagged group
./bootstrap.sh --skip image         # defaults minus one
./bootstrap.sh --list               # show every group and what it installs
```

## Inspecting the environment — `devtools`

After bootstrap, `devtools` is on your PATH (read-only; it never installs):

```bash
devtools report   # human-readable inventory, grouped by install group
devtools check    # verify every manifest tool is present (drift detection)
devtools doctor   # PATH, shellrc, runtimes, docker daemon, WSL filesystem health
```

The inventory lives in [`manifest/tools.json`](manifest/tools.json) — the source
of truth agents consult before installing anything. Agent rules:
[`docs/agent-rules.md`](docs/agent-rules.md).

### Agents auto-discover the environment

The bootstrap writes a marker-fenced block into `~/AGENTS.md` and `~/CLAUDE.md`
(machine-wide — Codex and Claude walk up to `$HOME`). So every AI session reads,
up front: this machine is provisioned by wsl-dev-envbuild; run `devtools report`
/ `devtools check` / `smoke-test` before installing; follow the uv/pnpm and
global-vs-local rules. The block is idempotent and uses distinct markers, so it
coexists with the AI Context Runner extension's own injected blocks. A good way
to confirm: ask the agent *"run `devtools report` and summarize what's
installed."*

## Layout

This repo:

```text
bootstrap.sh         entry point
lib/common.sh        shared helpers (has, apt_install, pipx_install, npm_global, …)
modules/*.sh         one file per install group
manifest/tools.json  agent-discoverable inventory
bin/devtools         report / check / doctor
docs/                architecture, agent-rules, wsl-filesystem
```

What it sets up in your home directory:

```text
~/projects/          active work (Linux filesystem — never /mnt/c)
~/sandboxes/         throwaway / untrusted analysis
~/tools/bin/         user scripts + tool shims on PATH (devtools, fd, bat, …)
~/tools/shellrc.sh   generated shell config, sourced once from ~/.bashrc
~/tools/logs/        bootstrap run logs
```

Exactly two base PATH additions (`~/.local/bin`, `~/tools/bin`); version
managers manage their own (e.g. `~/.cargo/bin`).

## Key conventions

- **Python:** `uv` for projects (and Python versions), `pipx` for global CLIs,
  never system `pip`.
- **Node:** `pnpm` + local `node_modules`; only `pnpm`/`tsx` global.
- **WSL filesystem:** work under `~/projects`, not `/mnt/c`
  ([`docs/wsl-filesystem.md`](docs/wsl-filesystem.md)).
- **Heavy/risky:** use containers, not the base system.

## Idempotency & safety

- Already-installed tools are detected and skipped (no duplicate work, no sudo
  when nothing's missing).
- User config (`.bashrc`) is backed up before any change; only a single
  sourcing line is added.
- Every run logs to `~/tools/logs/`.
- `optional-heavy` / `optional-gpu` never run without a flag.

## Requirements

- WSL2 with a Debian (trixie) distribution
- `sudo` access inside WSL
- Internet access for package downloads
- Recommended: enable systemd in `/etc/wsl.conf` (`[boot]\nsystemd=true`) so the
  Docker daemon starts automatically

## Extending

**Add a tool** (full step-by-step in [`docs/agent-rules.md`](docs/agent-rules.md)):
edit the right `modules/<group>.sh` — install it in `*_install` (guarded with
`has`) and record it in `*_record_manifest` (`manifest_add …`, guarded with
`if has <bin>`); then **run `./bootstrap.sh --only <group>`** to install it and
regenerate the manifest (never hand-edit `manifest/tools.json`); then **gate the
push on a green `devtools check` AND `smoke-test`** (a red smoke-test is a broken
build — fix before pushing); only then commit + push so other machines get it via
`git pull && ./bootstrap.sh`.

**Add a whole new group:** drop a `modules/<name>.sh` defining `<name>_desc` and
`<name>_install`, and add `<name>` to the group list in `bootstrap.sh`.
