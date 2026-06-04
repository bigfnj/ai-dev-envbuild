#!/usr/bin/env bash
# Shared helpers, sourced by bootstrap.sh and every module. Sourcing this file
# only DEFINES things — it must have no side effects. REPO_ROOT must already be
# exported by the caller.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing lib/common.sh}"

MANIFEST="$REPO_ROOT/manifest/tools.json"
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
    apt_refresh
    log_info "apt install: ${missing[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# pipx_install <package> — install a global Python CLI via pipx, idempotently.
# pipx isolates each app in its own venv under ~/.local/share/pipx and links the
# entry point into ~/.local/bin (already on PATH). Skips if already installed.
pipx_install() {
    local pkg="$1"
    has pipx || { log_err "pipx not installed; cannot pipx_install $pkg"; return 1; }
    if pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx "$pkg"; then
        log_skip "pipx: $pkg already installed"
        return 0
    fi
    log_info "pipx install $pkg"
    pipx install "$pkg"
}

# ── Filesystem / shell config ─────────────────────────────────────────────────
ensure_dir() { [ -d "$1" ] && return 0; mkdir -p "$1"; log_ok "mkdir $1"; }

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

# ── Manifest ──────────────────────────────────────────────────────────────────
# manifest_add name binary group scope install_method detect status [notes]
# Upserts by name into manifest/tools.json (the agent-discoverable inventory).
manifest_add() {
    local name="$1" binary="$2" group="$3" scope="$4" method="$5" detect="$6" status="$7" notes="${8:-}"
    ensure_dir "$(dirname "$MANIFEST")"
    [ -f "$MANIFEST" ] || echo '[]' > "$MANIFEST"
    local tmp; tmp="$(mktemp)"
    jq \
        --arg name "$name" --arg binary "$binary" --arg group "$group" \
        --arg scope "$scope" --arg method "$method" --arg detect "$detect" \
        --arg status "$status" --arg notes "$notes" --arg today "$TODAY" '
        . as $arr
        | ($arr | map(.name) | index($name)) as $i
        | { name:$name, binary:$binary, group:$group, scope:$scope,
            install_method:$method, detect:$detect, status:$status,
            notes:$notes, last_verified:$today } as $entry
        | if $i == null then $arr + [$entry] else ($arr | .[$i] = $entry) end
    ' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
}
