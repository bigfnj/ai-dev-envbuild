#!/usr/bin/env bash
# node — JavaScript / TypeScript runtime layer.
#
# Node.js comes from NodeSource (current LTS), not Debian's stale apt package.
# pnpm and tsx are the ONLY global JS tools, installed via npm into a USER
# prefix (~/.local) so there's no sudo and no /usr global-modules pollution —
# their bins land in ~/.local/bin, already on PATH (no third PATH entry).
#
# Everything else — TypeScript, ESLint, Prettier, Vite, frameworks — is
# project-local in node_modules (pnpm). See docs/architecture.md §4.

NODE_MAJOR=22

node_desc() { echo "Node.js (NodeSource LTS), pnpm, tsx"; }

node_install() {
    node_runtime
    node_global_tools
    node_record_manifest
}

# Install Node.js from NodeSource only if absent. Guarded so re-runs never
# re-add the apt repo or reinstall.
node_runtime() {
    if has node; then
        log_skip "node already installed ($(node --version))"
        return 0
    fi
    if is_dry_run; then
        log_info "[DRY-RUN] would add NodeSource repo (Node ${NODE_MAJOR}.x)"
        log_info "[DRY-RUN] would apt install: nodejs"
        return 0
    fi
    log_info "adding NodeSource repo (Node ${NODE_MAJOR}.x)"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
    apt_install nodejs
}

# pnpm + tsx via the shared npm_global helper (user prefix ~/.local, no sudo).
node_global_tools() {
    npm_global pnpm   # fast, disk-efficient package manager (preferred)
    npm_global tsx    # run .ts files directly, no build step
}

node_record_manifest() {
    if has node; then manifest_add nodejs node node global nodesource "node --version" core "current LTS via NodeSource apt repo"; fi
    if has npm;  then manifest_add npm   npm  node global nodesource "npm --version"  core "bundled with Node.js"; fi
    if has pnpm; then manifest_add pnpm  pnpm node global npm-user    "pnpm --version" core "preferred package manager (npm -g into ~/.local)"; fi
    if has tsx;  then manifest_add tsx   tsx  node global npm-user    "tsx --version"  core "run TypeScript files directly, no build step"; fi
    log_ok "manifest updated — node group"
}
