# Architecture — Debian/Ubuntu/WSL2 Swiss-Army Dev Environment

This document is the **why**. It locks the design decisions that every
`bootstrap.sh` module and helper script must follow. Read this before adding a
tool or changing an install method.

---

## 1. Executive summary

A single git repo reproduces a complete Debian/Ubuntu/WSL2 development workstation in
one command:

```bash
git clone git@github.com:bigfnj/ai-dev-envbuild.git
cd ai-dev-envbuild
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
ai-dev-envbuild/
  bootstrap.sh            entry point — runs install groups in order
  VERSION                 semver stamp (read by devtools; written to env-version)
  CHANGELOG.md            Keep-a-Changelog history
  lib/
    common.sh             shared helpers: logging, has(), apt_install(), backup(),
                          ensure_block(), write_agent_discovery(), manifest_add()
  modules/                one file per install group (sourced by bootstrap.sh)
    core.sh  python.sh  node.sh  languages.sh  reverse.sh
    data.sh  docs.sh  image.sh  containers.sh  mcp.sh
    optional-heavy.sh  optional-gpu.sh
  mcp-server/             devenv MCP server (Node) — exposes inventory tools as MCP
    index.js  denylist.json  package.json
  manifest/
    catalog.json          pre-bootstrap fallback tool catalog
  bin/
    devtools              report / check / doctor / outdated — agent + human discovery
    smoke-test            exercises the toolchain end-to-end (the build gate)
  hooks/
    pre-commit            runs devtools check; blocks the commit on manifest drift
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
  manifest/tools.json     machine-local generated inventory
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
| `core` | ✅ | apt CLI tools, build-essential, shell utilities, disk/env/secrets helpers, PATH + folder setup |
| `python` | ✅ | pipx, uv (also installs Python versions), ruff, ipython, jupyterlab |
| `node` | ✅ | NodeSource Node.js, pnpm, tsx |
| `languages` | ✅ | Rust (rustup), Go, .NET SDK, OpenJDK |
| `reverse` | ✅ | radare2, binwalk, exiftool, tshark, foremost, **dosbox-x (headless)**, Ghidra (+ Windows note) |
| `data` | ✅ | duckdb CLI, sqlite-utils, csvkit (pipx), rclone |
| `docs` | ✅ | pandoc, markdownlint-cli |
| `image` | ✅ | imagemagick, ffmpeg, yt-dlp, aria2 (system/media CLIs; Pillow/OpenCV stay project-local) |
| `containers` | ✅ | Docker CLI + Compose (WSL integration), devcontainer CLI |
| `mcp` | ✅ | devenv MCP server (exposes manifest tools) + registers MCP servers for Claude Code (user scope), Codex, VS Code, Cursor |
| `optional-heavy` | ⛔ flag | QEMU |
| `optional-gpu` | ⛔ flag | NVIDIA/CUDA WSL path, GPU PyTorch guidance |
| `agent-coding` | ⛔ flag | Ollama (system service) + local model fleet (barbell: default generalist + FIM/embedding specialists + on-demand 30B), aider, Continue — see §12 |

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

**`~/tools/manifest/tools.json` is the live source of truth.** Every module
appends/updates entries there during bootstrap based on the tools actually
present on the workstation. The repo tracks `manifest/catalog.json` only as a
pre-bootstrap fallback catalog, so machine-local installed versions and optional
tool state do not need to be committed. Schema per tool:

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
- `devtools check` — diff inventory vs reality (what's declared but missing, or
  present but undeclared); exit non-zero on drift
- `devtools doctor` — environment health (PATH sanity, version-manager init,
  WSL filesystem checks)

**`docs/agent-rules.md` is injected into `AGENTS.md`** so every AI session
reads, up front: check the inventory and run `devtools report` before proposing
an install; use `uv`/`pnpm` for project deps; never global `pip install`;
run bootstrap when tooling changes so the local inventory is regenerated.

**The `devenv` MCP server turns the inventory into live tools.** `modules/mcp.sh`
runs a small Node MCP server (`mcp-server/`) that exposes every global inventory
tool (minus a denylist) as a callable MCP tool, and registers it — plus github,
playwright, and context7 — in every agent config on the machine. It always
targets the scope that auto-loads with no per-project approval: **user scope**
for Claude Code (top-level `mcpServers` in `~/.claude.json` — Claude Code does
*not* read `~/.mcp.json` from `$HOME`), `[mcp_servers.*]` in
`~/.codex/config.toml` for Codex, and the `servers` key for VS Code / Cursor.
(Enterprise-managed Claude Code may gate server names via an
`allowedMcpServers` allowlist in `~/.claude/remote-settings.json`; a custom
server must be on that list to load, regardless of scope.)

---

## 7. Idempotency strategy

Re-running `bootstrap.sh` must be safe, fast, and non-destructive.

- **Detect before install** — every module guards with a `has <cmd>` check;
  already-present tools are skipped (logged as "ok"), not reinstalled.
- **Back up before overwrite** — any user config touched (`.bashrc`, etc.) is
  copied to `*.bak-<timestamp>` first; edits are marker-fenced and idempotent
  (re-running replaces the fenced block, never appends a duplicate).
- **Log every action** to `~/tools/logs/bootstrap-<timestamp>.log`.
- **Local inventory is regenerated, not appended blindly** — a full/default
  re-run reconciles `~/tools/manifest/tools.json` to current reality.
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

---

## 12. Local LLM agent-coding stack (optional)

`agent-coding` (opt-in: `--with agent-coding`) sets up a fully-local coding-assistant
stack on the workstation GPU: the ollama daemon, a model fleet, `aider`, and the
Continue VS Code extension. Design decisions and hard-won lessons:

**Single daemon — the `.deb` system service, never a per-user unit.** The ollama
`.deb` installs and enables a *system* service (`/etc/systemd/system/ollama.service`,
`User=ollama`, model store `/usr/share/ollama/.ollama/models`). The module enables
**that** and removes any legacy per-user unit. Running both is a real bug: two enabled
services race for `:11434`, and after a reboot the system unit wins the port — silently
serving a *different* model store than the one you populated. One daemon, one store.

**The model fleet is a "barbell," not one big model.**

- *Always-resident specialists* (tiny, co-loaded, ~1.7 GB combined):
  `qwen2.5-coder:1.5b-base` for fill-in-middle autocomplete and `mxbai-embed-large`
  for codebase embeddings.
- *Default generalist*: `mistral-small3.2:24b` — vision + reliable structured tool
  calls, fits full-GPU. The jack-of-all-trades for chat / edit / agent.
- *Fast chat/edit coder*: `qwen2.5-coder:14b`.
- *Load-on-demand heavyweights*: the ~18 GB 30B models (`qwen3-coder`,
  `qwen3:30b-a3b-thinking-2507-q4_K_M`) for deep coding/reasoning sessions.

Purpose-built mid-size models deliver more quality-per-VRAM than oversized generalists,
and tiny specialists co-reside; one generalist supplies the cross-domain glue.

**WSL2 single-allocation VRAM ceiling (the big lesson).** On WSL2/WDDM a single
`cudaMalloc` is capped at roughly **(free VRAM − ~4.5 GB)**, independent of total VRAM.
A 30B model loads its weights as one ~17.5 GB buffer, so on a 24 GB card it needs
~23 GB *free* to load full-GPU — true right after boot, but it OOMs once the Windows
desktop (browser, Wallpaper Engine, …) is using a couple GB. Field notes:

- Symptom: `cudaMalloc failed: out of memory` while `nvidia-smi` still shows 20+ GB free.
- `num_ctx` does **not** fix it — the failing buffer is the *weights*, not the KV cache.
- `OLLAMA_GPU_OVERHEAD` did **not** trigger auto-offload (ollama 0.30.7).
- Workaround when you must: `num_gpu` (partial CPU offload — works, but slower). Better:
  keep the 30B models load-on-demand; default to the always-fits generalist/vision models.
- Two ~18 GB models can never co-reside in 24 GB — load one at a time.

**Model gotchas worth remembering.**

- The Qwen3 *thinking* build ships **only quant-suffixed tags**
  (`qwen3:30b-a3b-thinking-2507-q4_K_M`, not a bare `…-2507`). `ollama pull` exits 0 on a
  missing manifest, so a wrong tag fails *silently* — verify tags before trusting a pull.
- A model's `tools` **capability flag ≠ reliable structured tool-calling**:
  `qwen2.5-coder` emits tool calls as inline JSON that ollama does not parse into
  `tool_calls`. Verify per model (`/api/chat` with a `tools` array) before using it in
  Agent mode; here it's marked chat/edit-only and agentic work routes to verified callers.

**Editor integration — Continue v2, and its config lives on the *Windows* side.**
The non-obvious part: the Continue VS Code extension here runs against the **Windows
host**, so it reads `%USERPROFILE%\.continue\config.yaml` (on this machine
`C:\Users\Admin\.continue\config.yaml`, i.e. `/mnt/c/Users/Admin/.continue/config.yaml`
from WSL) — **not** the Linux `~/.continue/config.yaml`. Editing the WSL copy silently
does nothing; the giveaway is the editor breadcrumb reading `C: > Users > Admin >
.continue`. (A WSL-remote Continue, if installed, reads the Linux home instead — the two
can diverge, so keep whichever instance you actually use authoritative.) The ollama daemon
stays in WSL; Continue reaches it at `http://localhost:11434` via WSL2 localhost forwarding,
which is also how an `AUTODETECT` config discovers the fleet.

- **Explicit `roles:`, never an `AUTODETECT` stub.** `model: AUTODETECT` makes Continue
  enumerate every ollama model and auto-assign roles arbitrarily — which silently routed
  `edit`/`apply` to the OOM-prone 30B thinking model. Each model declares its roles.
- **The 30B heavyweights are `chat`-only.** Edit (Ctrl+I) and Apply fire constantly and
  would cold-load an ~18 GB buffer — exactly the WSL single-allocation OOM above. So the
  30B models carry only `chat` (a deliberate Chat-dropdown opt-in for when VRAM is free),
  while `mistral-small3.2:24b` (default), `qwen2.5-coder:14b`, and `qwen3-vl:8b` hold
  `chat`/`edit`/`apply`. Continue makes the *first* model with a role that role's default,
  so the always-fits generalist is the edit/apply default and a heavyweight can never be.
- **Autocomplete and embeddings are decoupled** from the chat-model dropdown:
  `qwen2.5-coder:1.5b-base` (`autocomplete`) and `mxbai-embed-large` (`embed`) always run
  via their role-holder regardless of the selected chat model, with `tool_use` declared
  only where structured calls are verified.
- **`@codebase` indexing is gated by `.continuerc.json`** in that same dir
  (`"disableIndexing"`). It's enabled here (`false`), so `mxbai-embed-large` is the live
  embedder for `@codebase` / `@docs`; set it back to `true` to make the embed model dormant.
- **`config.yaml` wins over the legacy `config.json`** in that dir; the old `config.json`
  (the retired `qwen2.5vl:7b` / `qwen2.5-coder:32b` fleet) was moved aside to
  `config.json.bak`.
