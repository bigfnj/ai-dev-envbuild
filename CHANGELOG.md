# Changelog

All notable changes to ai-dev-envbuild are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `agent-coding` optional group (`--with agent-coding`) installs a local AI coding
  agent stack: Ollama daemon with VRAM-aware model selection
  (qwen2.5vl:7b for ≥12 GB, qwen2.5vl:3b for ≥5 GB, qwen2.5-coder:7b fallback),
  aider-chat CLI via pipx, and Continue (continue.dev) VS Code extension.
- `optional-gpu` now records FLUX.1-dev, FLUX.1-Fill-dev, Wan2.1-T2V, and
  Wan2.1-I2V checkpoint presence shims when their HuggingFace cache directories
  exist.
- `mcp` now registers an `ollama` MCP server alongside devenv/github/playwright/context7
  for Claude Code, Codex, VS Code, and Cursor.
- `smoke-test` now checks the Ollama daemon responds on :11434.
- `agent-coding` module includes a user systemd unit for Ollama autostart on WSL boot.

## [1.5.0] — 2026-06-11

### Added
- `core` now installs and records disk/env/secrets workflow helpers: `ncdu`,
  `duf`, `age`, `sops`, `direnv`, and `just`.
- `data` now installs and records `rclone` for cloud/local sync and artifact
  movement.
- `image` now installs and records `aria2` as a resumable/parallel downloader
  companion for `yt-dlp`.
- `smoke-test` now includes functional checks for the new workflow tools where
  they can be exercised offline: `just`, `age`, `sops`, `rclone`, and `direnv`.

### Fixed
- Full/default bootstrap runs now refresh the local inventory at
  `~/tools/manifest/tools.json` from the tools actually present on the
  workstation, preventing stale entries from optional groups or unavailable
  best-effort installs from causing `devtools check` drift. Targeted `--only`
  runs still preserve the existing local inventory.
- The repo now tracks `manifest/catalog.json` as a pre-bootstrap fallback while
  the machine-specific realized inventory stays outside git.

## [1.4.0] — 2026-06-11

### Added
- `image` now installs and records `yt-dlp` via pipx for media downloads;
  `ffmpeg` in the same group handles muxing, audio extraction, and conversion.

### Fixed
- `--dry-run` now reports intended `pipx` and npm-global installs even on a
  bare machine where `pipx` or `npm` is not installed yet.
- `--dry-run` skips git hook wiring and post-install writes such as agent
  discovery files, weekly cron registration, and the environment version stamp.
- `--dry-run` no longer writes core shell/PATH files, creates repo-bin symlinks,
  installs vendor apt repos, enables Docker services, changes Docker group
  membership, registers MCP configs, injects Pillow, or creates model shims.
- `--dry-run` now logs to stdout only instead of creating a bootstrap log file.

## [1.3.1] — 2026-06-10

### Added
- `optional-gpu` now records the **FLUX.1-Fill-dev** checkpoint
  (`flux-fill-dev-checkpoint`, ~55 GB, FLUX.1 [dev] non-commercial license) in
  the manifest via a presence-shim — recorded only when already cached, never
  auto-downloaded — matching the existing SDXL-inpaint pattern.

### Changed
- Corrected the SDXL-inpaint checkpoint size note (~7 GB → ~20 GB on disk;
  fp16+fp32 variants cached) and added its OpenRAIL++ license.
- `optional-gpu` guidance block now lists the image-gen checkpoints with
  accurate sizes + licenses and clarifies that project-local model files (e.g. a
  RealESRGAN `.pth`) are documented in the project's own `MODELS.md`, not the
  machine manifest.
- Docs de-staled: README layout + `docs/architecture.md` folder structure now
  include `mcp.sh`, `mcp-server/`, `bin/smoke-test`, `hooks/pre-commit`,
  `VERSION`, and `CHANGELOG.md`; README documents `devtools outdated`.

## [1.3.0] — 2026-06-10

### Added
- Agent-discovery block (`write_agent_discovery` in `lib/common.sh`) now notes
  that every inventory tool is runnable directly from the shell (`devtools
  report` lists them), and that the `devenv` MCP server is a convenience layer
  that managed MCP policy may block — so agents on locked-down machines know the
  shell path always works.
- Codex MCP registration — `modules/mcp.sh` now writes the four servers
  (devenv, github, playwright, context7) into `~/.codex/config.toml` as
  `[mcp_servers.*]` tables inside a managed comment-fenced block (idempotent;
  preserves any Codex config outside the fence). Verified via `codex mcp list`.

### Changed
- Claude Code MCP registration moved to **user scope** — servers are now written
  to the top-level `mcpServers` key in `~/.claude.json` (backed up first) instead
  of `~/.mcp.json`. Claude Code does not read `~/.mcp.json` from `$HOME`, and a
  project `.mcp.json` only loads after interactive approval; user scope is the
  only scope that auto-loads in every project with no prompt. This is the fix for
  "MCP servers should be available by default everywhere."

### Notes
- On enterprise-managed Claude Code installs, an org-pushed
  `~/.claude/remote-settings.json` `allowedMcpServers` allowlist gates which
  server *names* may load. A custom server like `devenv` will not appear unless
  the org adds it to that allowlist — independent of config scope. Documented as
  a gotcha in `modules/mcp.sh`. Codex has no such allowlist.

## [1.2.0] — 2026-06-08

### Added
- `verify_sha256` helper in `lib/common.sh` — warns when SHA256 is unpinned,
  errors on mismatch; called from github-zip and github-deb install functions.
- `source_repo` field in manifest (owner/repo slug) — `devtools outdated` now
  queries the GitHub Releases API to report the latest available version.
- `devtools outdated` — github releases section upgraded from "check manually"
  to live API comparison using `source_repo`.
- `--dry-run` flag on `bootstrap.sh` — sets `DRY_RUN=1`; all install helpers
  (`apt_install`, `pipx_install`, `npm_global`, `manifest_add`) print what they
  would do and return without side effects.
- Git hooks wiring — `bootstrap.sh` now runs `git config core.hooksPath hooks`
  so the committed `hooks/pre-commit` is active after every bootstrap.
- `hooks/pre-commit` — runs `devtools check` before each commit; aborts with a
  clear message if any manifest tool is missing.
- `mcp-server/denylist.json` — tools that must never be exposed as MCP tools
  (default: `frida`, `sshpass`). Loaded at server startup.
- `devtools outdated` — `compat_requires` warnings now cross-reference the
  newly outdated tool list to flag only relevant coupled upgrades.
- `.github/workflows/ci.yml` — shellcheck all shell scripts + validate that
  `manifest/tools.json` is valid JSON on every push and PR.

### Changed
- `manifest_add` extended with optional 10th param `source_repo`; existing
  callers unchanged (positional, param omitted = "").
- `modules/data.sh` — duckdb pinned to v1.5.3 (was: latest-at-bootstrap).
- `modules/reverse.sh` — radare2 pinned to 6.1.6; ghidra pinned to 12.1.
- MCP server version bumped to 1.2.0.

## [1.1.0] — 2026-05-15

### Added
- `devtools outdated` subcommand — apt, pipx, rustup, npm-global, github-zip/deb sections.
- `compat_requires` field in manifest — tracks tools that must stay version-compatible.
- `installed_version` captured in manifest at bootstrap time via detect command.
- `devenv` MCP server (`mcp-server/`) — exposes all 83 global tools as Claude Code tools.
- `~/.mcp.json` wiring — github, playwright, context7, devenv servers registered globally.
- `modules/mcp.sh` — installs devenv MCP server deps via pnpm, registers server.

## [1.0.0] — 2026-04-20

### Added
- Initial versioned release: core, python, node, languages, reverse, data, docs, image, containers groups.
- `bin/devtools` with report, check, doctor subcommands.
- `bin/smoke-test` — mandatory pre-push gate.
- `manifest/tools.json` — machine-readable tool inventory.
- Agent auto-discovery via `write_agent_discovery()` (AGENTS.md + CLAUDE.md).

[Unreleased]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/bigfnj/ai-dev-envbuild/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/bigfnj/ai-dev-envbuild/releases/tag/v1.0.0
