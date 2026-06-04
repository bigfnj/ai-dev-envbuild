# Architecture — WSL2 Debian Swiss-Army Dev Environment

This document is the **why**. It locks the design decisions that every
`bootstrap.sh` module and helper script must follow. Read this before adding a
tool or changing an install method.

---

## 1. Executive summary

A single git repo reproduces a complete WSL2 Debian development workstation in
one command:

```bash
git clone git@github.com:bigfnj/myai.git
cd myai/wsl-dev-envbuild
./bootstrap.sh
```

The environment is a broad "Swiss army knife" — modern dev across many
languages, legacy modernization, reverse engineering, image/media, office/PDF
automation, data science, and web research — without the usual rot: no giant
global Python env, no fragile mega-PATH, no duplicate installs, no rediscovery
by future AI agents.

Three ideas make it durable:

1. **Layered ownership** — every tool has exactly one install method and one
   home (system / pipx / project-local / container). Nothing is installed two
   ways.
2. **Idempotent, modular bootstrap** — re-running is safe and cheap; each
   workload is its own opt-in module.
3. **Agent-discoverable** — a machine-readable manifest plus a `devtools`
   reporting command means a human or AI can answer "what's installed, where,
   and how" before touching anything.

---

## 2. Recommended architecture

The environment is built in **layers**, each with a single owner. A tool lives
in exactly one layer — that is the rule that prevents duplication.

| Layer | Owner / install method | What lives here | Examples |
|---|---|---|---|
| **System** | `apt` (+ vendor apt repos) | Stable OS packages, durable CLI tools, compilers, build system | git, gcc/clang, ripgrep, jq, ffmpeg, tshark |
| **Runtimes** | Version managers / vendor installers | Language toolchains, kept off `apt`'s stale versions | Node (NodeSource), Rust (rustup), Go, .NET; Python versions via `uv` |
| **Global Python CLI** | `pipx` | Python *applications* used across projects, each in its own venv | ruff, jupyterlab, csvkit, frida |
| **Project-local** | `uv` / `pnpm` / `cargo` / etc. | All libraries and frameworks | pandas, flask, pytorch, react, scrapy |
| **Containers** | Docker / devcontainers | Heavy, risky, or version-pinned stacks | ML/CUDA, untrusted RE samples, client repros |

**Decision: `uv` is the Python project manager, `pipx` is the global-CLI
manager, system `pip` is never used directly.** This is the single most
important rule for keeping Python sane. Agents are told this explicitly in
`agent-rules.md`.

**Decision: no `pyenv`.** `uv` installs and manages Python versions itself
(`uv python install 3.x`) from prebuilt standalone builds — no compilation, no
build dependencies. Running pyenv alongside uv would duplicate version
management, which is precisely the duplication the spec forbids. uv is the one
owner of Python versions and project environments.

**Decision: language runtimes come from version managers / vendor repos, not
`apt`.** Debian stable ships old toolchains; rustup/NodeSource/pyenv give
current versions and per-user upgrades without `sudo`.

---

## 3. Folder structure

The repo (this sub-project):

```text
wsl-dev-envbuild/
  bootstrap.sh            entry point — runs install groups in order
  lib/
    common.sh             shared helpers: logging, has(), apt_install(), backup()
  modules/                one file per install group (sourced by bootstrap.sh)
    core.sh  python.sh  node.sh  languages.sh  reverse.sh
    data.sh  docs.sh  image.sh  containers.sh
    optional-heavy.sh  optional-gpu.sh
  manifest/
    tools.json            machine-readable inventory (the source of truth)
  bin/
    devtools              report / check / doctor — agent + human discovery
  docs/
    architecture.md       this file
    wsl-filesystem.md     Windows/WSL boundary guidance
    agent-rules.md        rules injected into AGENTS.md for AI agents
  README.md               one-liner install + overview
```

The **home-directory layout** the bootstrap establishes for the user:

```text
~/projects/               active work (Linux filesystem — never /mnt/c)
~/sandboxes/              throwaway experiments, untrusted analysis
~/tools/
  bin/                    user scripts on PATH (symlinks to bin/devtools etc.)
  logs/                   bootstrap run logs
~/.local/bin/             pipx shims (managed by pipx, added to PATH once)
```

**Decision: exactly two PATH additions** — `~/.local/bin` (pipx) and
`~/tools/bin` (our scripts). Version managers append their own single line via
their installers (cargo, etc.). No per-tool PATH entries — that is how the
"giant fragile PATH" is avoided.

---

## 4. Dependency model — global vs project-local

The boundary, stated as rules an agent can follow mechanically:

- **Global is for tools, not libraries.** A CLI you invoke by name from any
  directory (ruff, rg, ffmpeg, jq) may be global. A library you `import`
  belongs in a project.
- **Python libraries → `uv` in a project `.venv`.** Never `pip install` into
  system Python. Never `pipx` a library. **`pytest`, `mypy`, and other dev
  tools belong here too** (`uv add --dev`), not global — a global `pytest`
  can't import the project's deps or plugins.
- **Node packages → local `node_modules` via `pnpm`.** Only `tsx` and `pnpm`
  itself are global.
- **Heavy/conflicting/risky → container.** PyTorch+CUDA, an untrusted binary,
  a client's exact toolchain — these get a devcontainer, not the base system.

A new project is initialized from a template (`uv init`, `pnpm create`, etc.)
so the local-first default is the path of least resistance.

---

## 5. Install groups

`bootstrap.sh` runs groups in dependency order. Each maps to one
`modules/*.sh`. Default groups run automatically; `optional-*` require an
explicit flag.

| Group | Default? | Contents |
|---|---|---|
| `core` | ✅ | apt CLI tools, build-essential, shell utilities, PATH + folder setup |
| `python` | ✅ | pipx, uv (also installs Python versions), ruff, ipython, jupyterlab |
| `node` | ✅ | NodeSource Node.js, pnpm, tsx |
| `languages` | ✅ | Rust (rustup), Go, .NET SDK, OpenJDK |
| `reverse` | ✅ | radare2, binwalk, exiftool, tshark, foremost, **dosbox-x (headless)**, Ghidra (+ Windows note) |
| `data` | ✅ | duckdb CLI, sqlite-utils, csvkit (pipx) |
| `docs` | ✅ | pandoc, markdownlint-cli |
| `image` | ✅ | imagemagick, ffmpeg (system CLIs; Pillow/OpenCV stay project-local) |
| `containers` | ✅ | Docker CLI + Compose (WSL integration), devcontainer CLI |
| `optional-heavy` | ⛔ flag | QEMU |
| `optional-gpu` | ⛔ flag | NVIDIA/CUDA WSL path, GPU PyTorch guidance |

```bash
./bootstrap.sh                      # all default groups
./bootstrap.sh --only core,python   # just these
./bootstrap.sh --with optional-gpu  # defaults + a flagged group
./bootstrap.sh --list               # show groups and what each installs
```

---

## 6. Agent discoverability

The environment must answer, for a human or an AI agent, *before* anything new
is installed: what's installed, where, how, and is it global or project-scoped.

**`manifest/tools.json` is the source of truth.** Every module appends/updates
its entries. Schema per tool:

```json
{
  "name": "ripgrep",
  "binary": "rg",
  "group": "core",
  "scope": "global",
  "install_method": "apt",
  "detect": "rg --version",
  "status": "core",
  "notes": "fast recursive search",
  "last_verified": "2026-06-04"
}
```

`scope` ∈ `global | project-local | container`; `status` ∈
`core | optional | experimental | isolated`.

**`bin/devtools` is the interface:**

- `devtools report` — human-readable inventory grouped by layer
- `devtools check` — diff manifest vs reality (what's declared but missing, or
  present but undeclared); exit non-zero on drift
- `devtools doctor` — environment health (PATH sanity, version-manager init,
  WSL filesystem checks)

**`docs/agent-rules.md` is injected into `AGENTS.md`** so every AI session
reads, up front: check the manifest and run `devtools report` before proposing
an install; use `uv`/`pnpm` for project deps; never global `pip install`;
update `tools.json` when tooling changes.

---

## 7. Idempotency strategy

Re-running `bootstrap.sh` must be safe, fast, and non-destructive.

- **Detect before install** — every module guards with a `has <cmd>` check;
  already-present tools are skipped (logged as "ok"), not reinstalled.
- **Back up before overwrite** — any user config touched (`.bashrc`, etc.) is
  copied to `*.bak-<timestamp>` first; edits are marker-fenced and idempotent
  (re-running replaces the fenced block, never appends a duplicate).
- **Log every action** to `~/tools/logs/bootstrap-<timestamp>.log`.
- **Manifest is regenerated, not appended blindly** — a re-run reconciles
  `tools.json` to current reality.
- **No massive optional stacks by default** — `optional-heavy` / `optional-gpu`
  never run without an explicit flag.

---

## 8. WSL filesystem guidance

(Full detail in [`wsl-filesystem.md`](wsl-filesystem.md).)

- **Active projects live on the Linux filesystem (`~/projects`), never
  `/mnt/c`.** Cross-OS filesystem calls are an order of magnitude slower and
  break inotify file-watchers (Vite, nodemon, pytest-watch).
- `/mnt/c` is acceptable for one-off reads of Windows-side files or sharing a
  final artifact — not for a working tree.
- VS Code opens project folders through **Remote - WSL** so the server runs
  inside Linux.
- Git is configured inside WSL; credentials/SSH keys live in WSL (`~/.ssh`).

---

## 9. GPU / CUDA (optional, isolated)

GPU is **never assumed**. The base environment is CPU-only. `optional-gpu`
documents and optionally sets up:

- NVIDIA driver on the **Windows host** (the WSL CUDA stack rides on it — you do
  not install a Linux NVIDIA driver inside WSL).
- CUDA toolkit inside WSL only if building CUDA code.
- GPU PyTorch/TensorFlow as **project-local or containerized** installs, never
  global.

Kept entirely separate so the common case stays lean.

---

## 10. GUI tools — WSL vs Windows vs container

WSLg runs Linux GUIs, but for heavy GUI apps a Windows-native install is often
smoother. Decisions:

| Tool | Recommendation | Why |
|---|---|---|
| Ghidra | **WSL install by default** (OpenJDK + release tarball); Windows-native documented as alternative | Actively used; Java app runs fine under WSLg, and keeping it in WSL keeps projects co-located |
| ImHex | Windows-native preferred | Native build smoother than WSLg |
| Wireshark | **tshark** in WSL; Wireshark GUI on Windows | CLI capture covers WSL needs; GUI better native |
| DOSBox-X | **WSL, headless** (in `reverse` group) | Driven for automated/scripted DOS-era binary analysis, not interactive play |
| Risky/unknown binaries | **Container or `~/sandboxes`** | Isolation over convenience |

**Headless DOSBox-X:** installed in the default `reverse` group and run without
a display for scripted analysis pipelines — `SDL_VIDEODRIVER=dummy dosbox-x
-conf <headless.conf> ...`. The bootstrap drops a reusable headless config and a
`~/tools/bin` wrapper so an agent or script can launch DOS-era binaries,
capture output, and tear down without a window or WSLg. Interactive GUI use
still works via WSLg when a display is available, but is not the default mode.

---

## 11. Maintenance

- **Add a tool:** put it in the right module, guard it with `has`, add its
  `tools.json` entry. Run `devtools check` to confirm no drift.
- **Upgrade runtimes:** via their version managers (`rustup update`,
  `pyenv install`, etc.), not `apt`.
- **Verify after changes:** `devtools doctor` for environment health,
  `devtools report` for the human-readable inventory.
- **Re-provision a new machine:** clone, run `bootstrap.sh`. The manifest and
  this doc travel with the repo, so the next machine — and the next agent — start
  from full knowledge, not rediscovery.
