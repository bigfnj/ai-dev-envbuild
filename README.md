# ai-dev-envbuild

> **Environment version: 1.7.0** — run `devtools report` to see what's installed, `devtools doctor` to check for drift.

Reproducible, idempotent, agent-discoverable **Debian/Ubuntu/WSL2 development
environment** — a broad "Swiss army knife" workstation (modern dev, legacy
modernization, reverse engineering, image/media, office/PDF, data science, web
research) provisioned from one command.

```bash
git clone git@github.com:bigfnj/ai-dev-envbuild.git
cd ai-dev-envbuild
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
| `core` | ✅ | git, build toolchain, ripgrep/fd/fzf/bat/jq/delta, tmux, shellcheck, **gh**, **hyperfine**, **GNU time**, **ncdu/duf**, **age/sops**, **direnv**, **just** (+ folders, PATH, `devtools`) |
| `python` | ✅ | pipx, uv (also Python versions), ruff, ipython, jupyterlab |
| `node` | ✅ | Node.js (NodeSource), pnpm, tsx |
| `languages` | ✅ | Rust (rustup + **rust-analyzer**), Go, OpenJDK + Maven, .NET |
| `reverse` | ✅ | radare2, binwalk, exiftool, tshark, foremost, **headless DOSBox-X**, frida, **Ghidra** |
| `data` | ✅ | DuckDB CLI, sqlite-utils, csvkit, **rclone** |
| `docs` | ✅ | pandoc, markdownlint-cli |
| `image` | ✅ | ImageMagick, ffmpeg, **Pillow** (pipx-injected into ipython), **yt-dlp**, **aria2** |
| `containers` | ✅ | Docker Engine + Compose, devcontainer CLI |
| `mcp` | ✅ | **devenv MCP server** (exposes manifest tools) + registers devenv/github/playwright/context7 for Claude Code, Codex, VS Code, Cursor |
| `optional-heavy` | ⛔ flag | QEMU |
| `optional-gpu` | ⛔ flag | NVIDIA/CUDA detection + guidance |
| `agent-coding` | ⛔ flag | Ollama (system service) + VRAM-aware barbell fleet — Mistral-Small 3.2 default, Qwen3-Coder/Thinking 30B on-demand, Qwen3-VL 8B, qwen2.5-coder:14b chat/edit, FIM autocomplete + mxbai embeddings + aider + Continue |

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
devtools doctor   # PATH, shellrc, runtimes, docker daemon health
devtools outdated # check for newer versions (apt/pipx/rustup/npm + GitHub releases)
```

The live inventory lives in `~/tools/manifest/tools.json` and is generated from
this workstation's actual installed tools. The repo carries
[`manifest/catalog.json`](manifest/catalog.json) as a pre-bootstrap fallback
catalog. Agent rules:
[`docs/agent-rules.md`](docs/agent-rules.md).

### Agents auto-discover the environment

The bootstrap writes a marker-fenced block into `~/AGENTS.md` and `~/CLAUDE.md`
(machine-wide — Codex and Claude walk up to `$HOME`). So every AI session reads,
up front: this machine is provisioned by ai-dev-envbuild; run `devtools report`
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
modules/*.sh         one file per install group (core … containers, mcp, optional-*)
mcp-server/          devenv MCP server — exposes inventory tools to agents
manifest/catalog.json pre-bootstrap fallback tool catalog
bin/devtools         report / check / doctor / outdated
bin/smoke-test       end-to-end toolchain gate
hooks/pre-commit     blocks commits on manifest drift
docs/                architecture, agent-rules, wsl-filesystem
```

What it sets up in your home directory:

```text
~/projects/          active work (Linux filesystem — never /mnt/c)
~/sandboxes/         throwaway / untrusted analysis
~/tools/bin/         user scripts + tool shims on PATH (devtools, fd, bat, …)
~/tools/manifest/    generated machine-local inventory (tools.json; not committed)
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

- Debian (trixie) or Ubuntu (24.04+), either native or via WSL2
- `sudo` access
- Internet access for package downloads
- WSL2: recommended to enable systemd in `/etc/wsl.conf` (`[boot] systemd=true`)
  so the Docker daemon starts automatically

## Versioning

The repo carries a [`VERSION`](VERSION) file (semver). Every `bootstrap.sh` run
stamps the installed version and date into `~/tools/env-version`:

```text
1.5.0  2026-06-11
```

`devtools report` shows the installed version at the top. `devtools doctor`
flags a mismatch between the installed stamp and the repo `VERSION` — a
reminder to re-run `./bootstrap.sh` after a `git pull`. Bump `VERSION` whenever
a new tool is added or a group is meaningfully changed.

### Changelog

| Version | Change |
|---------|--------|
| **1.5.0** | Adds `aria2`, `rclone`, `ncdu`, `duf`, `age`, `sops`, `direnv`, and `just`, plus smoke-test coverage for the new workflow tools. |
| **1.4.0** | `image` installs and records `yt-dlp` via pipx for media downloads; `ffmpeg` in the same group handles muxing, audio extraction, and conversion. |
| **1.3.1** | `optional-gpu` records the FLUX.1-Fill-dev checkpoint (~55 GB, non-commercial license) via presence-shim and corrects the SDXL size (~20 GB) — both recorded only when already cached, never auto-downloaded. |
| **1.3.0** | Codex MCP registration (`~/.codex/config.toml`); Claude Code MCP moved to **user scope** (`~/.claude.json`) so servers load by default everywhere — the old `~/.mcp.json` was never read from `$HOME`. See `CHANGELOG.md` for the managed-allowlist gotcha. |
| **1.2.0** | `devtools outdated` live GitHub-release checks (`source_repo`); SHA256 pinning (`verify_sha256`); `--dry-run`; pre-commit gate wired via `core.hooksPath`; CI (shellcheck + manifest JSON); MCP server denylist; cross-platform `detect` fallback |
| **1.1.0** | Expanded `write_agent_discovery` to inline full install rules into `~/CLAUDE.md` and `~/AGENTS.md` — all agents on all projects now see Python/ML/system install constraints without needing to discover `docs/agent-rules.md` |
| **1.0.0** | Initial stable release — versioning, README refresh, Pillow remediation |

## Extending

**Add a tool** (full step-by-step in [`docs/agent-rules.md`](docs/agent-rules.md)):
edit the right `modules/<group>.sh` — install it in `*_install` (guarded with
`has`) and record it in `*_record_manifest` (`manifest_add …`, guarded with
`if has <bin>`); then **run `./bootstrap.sh --only <group>`** to install it and
update the local inventory (never hand-edit `~/tools/manifest/tools.json`); then
**gate the push on a green `devtools check` AND `smoke-test`** (a red smoke-test
is a broken build — fix before pushing); only then commit + push so other
machines get it via `git pull && ./bootstrap.sh`.

**Add a whole new group:** drop a `modules/<name>.sh` defining `<name>_desc` and
`<name>_install`, and add `<name>` to the group list in `bootstrap.sh`.
