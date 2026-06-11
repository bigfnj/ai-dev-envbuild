#!/usr/bin/env bash
# Shared helpers, sourced by bootstrap.sh and every module. Sourcing this file
# only DEFINES things — it must have no side effects. REPO_ROOT must already be
# exported by the caller.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing lib/common.sh}"

CATALOG="$REPO_ROOT/manifest/catalog.json"
MANIFEST="${DEVENV_MANIFEST:-$HOME/tools/manifest/tools.json}"
# shellcheck disable=SC2034  # consumed by bootstrap.sh — this file is sourced
LOG_DIR="$HOME/tools/logs"
TODAY="$(date +%Y-%m-%d)"

# ── Logging ───────────────────────────────────────────────────────────────────
# Color only when stdout is a terminal; degrades to plain text in log files.
_c() { if [ -t 1 ]; then printf '\033[%sm' "$1"; fi; }
log_info()  { printf '%sℹ%s  %s\n' "$(_c 36)" "$(_c 0)" "$*"; }
log_ok()    { printf '%s✓%s  %s\n' "$(_c 32)" "$(_c 0)" "$*"; }
log_skip()  { printf '%s•%s  %s\n' "$(_c 90)" "$(_c 0)" "$*"; }
log_warn()  { printf '%s⚠%s  %s\n' "$(_c 33)" "$(_c 0)" "$*" >&2; }
log_err()   { printf '%s✗%s  %s\n' "$(_c 31)" "$(_c 0)" "$*" >&2; }
log_group() { printf '\n%s== %s ==%s\n' "$(_c 1)" "$*" "$(_c 0)"; }

# ── Detection ─────────────────────────────────────────────────────────────────
has()           { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
is_dry_run()    { [ "${DRY_RUN:-0}" = "1" ]; }
is_wsl()        { grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; }

# ── apt ───────────────────────────────────────────────────────────────────────
_APT_UPDATED=0
apt_refresh() {
    if [ "$_APT_UPDATED" -eq 0 ]; then
        log_info "apt-get update"
        sudo apt-get update -qq
        _APT_UPDATED=1
    fi
}

# apt_install <pkg> [pkg...] — installs only packages not already present.
# Idempotent: a fully-satisfied call does no network work and logs a skip.
apt_install() {
    local p missing=()
    for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
    if [ ${#missing[@]} -eq 0 ]; then
        log_skip "apt: all present ($*)"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would apt install: ${missing[*]}"; return 0; fi
    apt_refresh
    log_info "apt install: ${missing[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# pipx_install <package> — install a global Python CLI via pipx, idempotently.
# pipx isolates each app in its own venv under ~/.local/share/pipx and links the
# entry point into ~/.local/bin (already on PATH). Skips if already installed.
pipx_install() {
    local pkg="$1"
    if is_dry_run; then log_info "[DRY-RUN] would pipx install $pkg"; return 0; fi
    has pipx || { log_err "pipx not installed; cannot pipx_install $pkg"; return 1; }
    if pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$pkg"; then
        log_skip "pipx: $pkg already installed"
        return 0
    fi
    log_info "pipx install $pkg"
    pipx install "$pkg"
}

# npm_global <package> [binary] — install a global npm CLI into a USER prefix
# (~/.local) so there's no sudo and no /usr global-modules pollution; the bin
# reuses the ~/.local/bin PATH entry. Ensures the prefix once, idempotent.
npm_global() {
    local pkg="$1" bin="${2:-$1}"
    if is_dry_run; then log_info "[DRY-RUN] would npm install -g $pkg"; return 0; fi
    has npm || { log_err "npm not installed; cannot npm_global $pkg"; return 1; }
    if [ "$(npm config get prefix)" != "$HOME/.local" ]; then
        npm config set prefix "$HOME/.local"
        log_ok "npm global prefix -> ~/.local (user-owned, no sudo)"
    fi
    if has "$bin"; then
        log_skip "npm -g: $pkg already present ($bin)"
        return 0
    fi
    log_info "npm install -g $pkg"
    npm install -g "$pkg"
}

# ── Filesystem / shell config ─────────────────────────────────────────────────
ensure_dir() {
    [ -d "$1" ] && return 0
    if is_dry_run; then log_info "[DRY-RUN] would mkdir $1"; return 0; fi
    mkdir -p "$1"; log_ok "mkdir $1"
}

backup_file() {
    [ -f "$1" ] || return 0
    local b
    b="$1.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$1" "$b"
    log_info "backed up $(basename "$1") -> $(basename "$b")"
}

# ensure_line <file> <line> — append a line once. Backs the file up the first
# time it has to change it. We keep generated shell config in its own file
# (~/tools/shellrc.sh) and only ever add ONE sourcing line to .bashrc, so this
# is all the .bashrc surgery the bootstrap needs.
ensure_line() {
    local file="$1" line="$2"
    ensure_dir "$(dirname "$file")"
    [ -f "$file" ] || touch "$file"
    if grep -qxF "$line" "$file"; then
        log_skip "line already in $(basename "$file")"
    else
        backup_file "$file"
        printf '%s\n' "$line" >> "$file"
        log_ok "added sourcing line to $(basename "$file")"
    fi
}

# ensure_block <file> <marker> <body> — idempotently maintain an HTML-comment
# marker-fenced block in a file, replacing it in place if present (preserving
# everything else) or appending it if absent. Distinct markers mean our block
# coexists with other tools' blocks in the same file (e.g. the AI Context Runner
# extension's AI_CTX block in AGENTS.md). Body may be multi-line.
ensure_block() {
    local file="$1" marker="$2" body="$3"
    local start="<!-- ${marker}_START -->" end="<!-- ${marker}_END -->"
    ensure_dir "$(dirname "$file")"
    [ -f "$file" ] || : > "$file"
    local bf tmp; bf="$(mktemp)"; tmp="$(mktemp)"
    printf '%s\n' "$body" > "$bf"
    if grep -qF "$start" "$file"; then
        backup_file "$file"
        # Replace in place: keep start/end, swap the body between them.
        awk -v s="$start" -v e="$end" -v bf="$bf" '
            $0==s { print; while ((getline l < bf) > 0) print l; close(bf); inblk=1; next }
            $0==e { inblk=0; print; next }
            inblk!=1 { print }
        ' "$file" > "$tmp"
    else
        { cat "$file"; printf '\n%s\n' "$start"; cat "$bf"; printf '%s\n' "$end"; } > "$tmp"
    fi
    mv "$tmp" "$file"; rm -f "$bf"
    log_ok "agent block [$marker] -> $file"
}

# Materialize machine-wide agent-discovery files so any AI agent (Codex reads
# AGENTS.md, Claude reads CLAUDE.md, walking up to $HOME) learns the environment
# and is told to inspect it before installing. Marker-fenced + idempotent, so it
# coexists with the AI Context Runner extension's own injected blocks.
write_agent_discovery() {
    local body
    body="$(cat <<EOF
# Dev environment — ai-dev-envbuild (machine-wide)

This machine is provisioned by ai-dev-envbuild (repo: $REPO_ROOT).

## Before installing anything

Run these first — the tool you want is probably already here:
  - \`devtools report\`    — full tool inventory
  - \`devtools check\`     — verify everything is present
  - \`devtools outdated\`  — check for newer versions; flags compat constraints
  - \`smoke-test\`         — exercise the toolchain end-to-end

Every inventory tool is runnable directly from the shell — \`devtools report\`
lists them all. (A \`devenv\` MCP server also exposes them as MCP tools, but
managed MCP policy may block it; the shell path always works.)

Full rules: $REPO_ROOT/docs/agent-rules.md

## Install rules (follow exactly — violations cause environment rot)

**Python libraries** (anything you \`import\`):
  - Project-local ONLY: \`uv add <pkg>\` inside a project with a \`pyproject.toml\`.
  - NEVER \`uv pip install\` (untracked, breaks on next \`uv sync\`).
  - NEVER \`pip install\` or \`pip3 install\` into system Python.
  - NEVER \`pipx\` a library.

**Python CLI tools** (things you invoke by name, e.g. ruff, ipython):
  - \`pipx install <pkg>\` — each gets its own isolated venv.

**ML / CUDA / heavy stacks** (PyTorch, ONNX, Triton, large model weights):
  - Container or devcontainer. NOT the base system, even via pipx.
  - Exception: if the project already has a GPU venv, add to its pyproject.toml.

**System tools** (ripgrep, ffmpeg, jq, …):
  - \`apt\` only, via the right \`modules/<group>.sh\`.

**Node packages**: \`pnpm\` for project deps; nothing global except pnpm + tsx.

## Adding a tool to this repo (mandatory steps — do not skip any)

1. Edit \`modules/<group>.sh\`: add install call in \`*_install\` and \`manifest_add\` in \`*_record_manifest\`.
2. \`./bootstrap.sh --only <group>\` — installs the tool AND updates the local inventory.
3. \`devtools check\` — must show no drift.
4. \`smoke-test\` — must exit 0. Red = broken build; fix before pushing.
5. Only then: \`git add -A && git commit && git push\`.

## Inventory of record

$MANIFEST

Repo fallback catalog: $CATALOG
EOF
)"
    ensure_block "$HOME/AGENTS.md" "DEVENV_RULES" "$body"
    ensure_block "$HOME/CLAUDE.md" "DEVENV_RULES" "$body"
}

# ── SHA256 verification ───────────────────────────────────────────────────────
# verify_sha256 <file> <expected_sha256>
# When expected is empty: warn and print the actual hash (so the operator can
# pin it), then return 0 (non-blocking). When provided and mismatched: error
# and return 1, aborting the calling function.
verify_sha256() {
    local file="$1" expected="$2"
    local actual; actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ -z "$expected" ]; then
        log_warn "SHA256 not pinned for $(basename "$file") — actual: $actual"
        log_warn "Pin it: set SHA256=\"$actual\" in the module"
        return 0
    fi
    if [ "$actual" != "$expected" ]; then
        log_err "SHA256 MISMATCH for $(basename "$file")"
        log_err "  expected: $expected"
        log_err "  actual:   $actual"
        return 1
    fi
    log_ok "SHA256 verified: $(basename "$file")"
}

# ── Manifest ──────────────────────────────────────────────────────────────────
# manifest_add name binary group scope install_method detect status [notes] [compat_requires] [source_repo]
#
# Upserts by name into the machine-local agent-discoverable inventory.
#
# compat_requires: space-separated list of other manifest tool names that must
# stay version-compatible with this one (e.g. "ipython" for pillow, "rust" for
# rust-analyzer). devtools outdated uses this to warn when a coupled upgrade is
# needed. Omit or pass "" to leave unconstrained.
#
# source_repo: "owner/repo" GitHub slug. devtools outdated uses this to query
# the GitHub API for the latest release and compare to installed_version.
manifest_add() {
    local name="$1" binary="$2" group="$3" scope="$4" method="$5" detect="$6" status="$7"
    local notes="${8:-}" compat_requires="${9:-}" source_repo="${10:-}"

    if is_dry_run; then
        log_info "[DRY-RUN] would manifest_add $name ($binary)"
        return 0
    fi

    ensure_dir "$(dirname "$MANIFEST")"
    [ -f "$MANIFEST" ] || echo '[]' > "$MANIFEST"

    # Capture installed version: run the detect command, pull the first
    # semver-like token from its output. Empty string when detection fails.
    local installed_version=""
    if [ -n "$detect" ]; then
        installed_version="$(bash -c "$detect" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1 || true)"
    fi

    # Convert optional space-separated compat list to a JSON array.
    local compat_json="[]"
    if [ -n "$compat_requires" ]; then
        compat_json="$(printf '%s' "$compat_requires" \
            | tr ' ' '\n' | jq -R . | jq -sc .)"
    fi

    local tmp; tmp="$(mktemp)"
    jq \
        --arg  name              "$name"              \
        --arg  binary            "$binary"            \
        --arg  group             "$group"             \
        --arg  scope             "$scope"             \
        --arg  method            "$method"            \
        --arg  detect            "$detect"            \
        --arg  status            "$status"            \
        --arg  notes             "$notes"             \
        --arg  today             "$TODAY"             \
        --arg  installed_version "$installed_version" \
        --arg  source_repo       "$source_repo"       \
        --argjson compat_requires "$compat_json" '
        . as $arr
        | ($arr | map(.name) | index($name)) as $i
        | {
            name:              $name,
            binary:            $binary,
            group:             $group,
            scope:             $scope,
            install_method:    $method,
            detect:            $detect,
            status:            $status,
            notes:             $notes,
            last_verified:     $today,
            installed_version: $installed_version,
            compat_requires:   $compat_requires,
            source_repo:       $source_repo
          } as $entry
        | if $i == null then $arr + [$entry] else ($arr | .[$i] = $entry) end
    ' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
}
