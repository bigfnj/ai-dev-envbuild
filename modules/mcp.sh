#!/usr/bin/env bash
# mcp — MCP server registration for Claude Code, Codex, VS Code Copilot, Cursor.
#
# Installs Node.js dependencies for the devenv MCP server, then registers all
# four servers (devenv, github, playwright, context7) in every agent config
# detected on this machine — always choosing the scope that makes them load BY
# DEFAULT in every session/project, with no per-project approval prompt:
#
#   Claude Code : ~/.claude.json         (top-level "mcpServers" = USER scope)
#   Codex       : ~/.codex/config.toml   ([mcp_servers.*], managed fenced block)
#   VS Code     : %APPDATA%/Code/User/mcp.json   (servers key, type:stdio)
#   Cursor      : %APPDATA%/Cursor/User/mcp.json (servers key, type:stdio)
#
# Scope is the whole point. Claude Code does NOT read ~/.mcp.json from $HOME,
# and a project-root .mcp.json only activates after interactive approval
# (⏸ "pending approval"). The top-level "mcpServers" key in ~/.claude.json is
# USER scope — the only one that auto-loads in every project with no prompt — so
# that is what we write. Codex reads ~/.codex/config.toml unconditionally.
#
# VS Code and Cursor configs are only written when the respective Windows
# AppData directories exist. Path resolution is dynamic via cmd.exe + wslpath,
# so this works on any WSL2 machine regardless of Windows username.
#
# GOTCHA — managed Claude Code policy: on enterprise-managed installs, an
# org-pushed ~/.claude/remote-settings.json may carry an "allowedMcpServers"
# allowlist. Claude Code loads ONLY servers whose name is on that list, no
# matter what scope we write. If "devenv" is absent there, Claude Code will
# silently refuse it (it won't even show in `claude mcp list`) — the fix is to
# have the org add "devenv" to the allowlist, not to change anything here.
# Codex has no such allowlist, so devenv works there regardless.

mcp_desc() { echo "devenv MCP server — exposes manifest tools to Claude Code, Codex, VS Code, Cursor"; }

mcp_install() {
    mcp_install_deps
    mcp_register
    mcp_register_agent_coding
}

mcp_install_deps() {
    if is_dry_run; then log_info "[DRY-RUN] would install MCP server node dependencies"; return 0; fi
    has pnpm || { log_err "pnpm not installed — run the node group first"; return 1; }
    log_info "installing MCP server node dependencies"
    ( cd "$REPO_ROOT/mcp-server" && pnpm install --frozen-lockfile 2>/dev/null || pnpm install )
    log_ok "MCP server dependencies installed"
}

# Resolve Windows %APPDATA% as a WSL path. Returns empty string if cmd.exe or
# wslpath are unavailable (non-WSL environment).
_mcp_win_appdata() {
    local raw
    raw="$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n')" || return 0
    [ -n "$raw" ] && wslpath "$raw" 2>/dev/null || true
}

# Write the four servers at USER scope into a Claude config — the top-level
# "mcpServers" key, which loads in every project with no approval prompt. All
# other keys are preserved: ~/.claude.json also holds session/auth/project
# state, so we merge in place (and back up first).
_mcp_write_claude_fmt() {
    local dest="$1" server_path="$2"
    backup_file "$dest"
    [ -f "$dest" ] || printf '{}\n' > "$dest"
    MCP_JSON="$dest" SERVER_PATH="$server_path" node --input-type=module <<'EOF'
import { readFileSync, writeFileSync } from "fs";
const cfg = JSON.parse(readFileSync(process.env.MCP_JSON, "utf8"));
cfg.mcpServers = cfg.mcpServers ?? {};
cfg.mcpServers.devenv     = { type: "stdio", command: "node", args: [process.env.SERVER_PATH] };
cfg.mcpServers.github     = { type: "stdio", command: "sh", args: ["-c", "GITHUB_TOKEN=$(gh auth token) npx -y @modelcontextprotocol/server-github"] };
cfg.mcpServers.playwright = { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp"] };
cfg.mcpServers.context7   = { type: "stdio", command: "npx", args: ["-y", "@upstash/context7-mcp"] };
cfg.mcpServers.ollama    = { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-ollama"] };
writeFileSync(process.env.MCP_JSON, JSON.stringify(cfg, null, 2) + "\n");
EOF
}

# Write the four servers into a VS Code / Cursor style config (servers key +
# type:stdio). Used by both VS Code Copilot and Cursor — same format.
_mcp_write_vscode_fmt() {
    local dest="$1" server_path="$2"
    [ -f "$dest" ] || printf '{"servers":{}}\n' > "$dest"
    MCP_JSON="$dest" SERVER_PATH="$server_path" node --input-type=module <<'EOF'
import { readFileSync, writeFileSync } from "fs";
const cfg = JSON.parse(readFileSync(process.env.MCP_JSON, "utf8"));
cfg.servers = cfg.servers ?? {};
cfg.servers.devenv    = { type: "stdio", command: "node", args: [process.env.SERVER_PATH] };
cfg.servers.github    = { type: "stdio", command: "sh", args: ["-c", "GITHUB_TOKEN=$(gh auth token) npx -y @modelcontextprotocol/server-github"] };
cfg.servers.playwright = { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp"] };
cfg.servers.context7  = { type: "stdio", command: "npx", args: ["-y", "@upstash/context7-mcp"] };
cfg.servers.ollama   = { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-ollama"] };
writeFileSync(process.env.MCP_JSON, JSON.stringify(cfg, null, 2) + "\n");
EOF
}

# Write the four servers into Codex's TOML config as [mcp_servers.*] tables,
# inside a managed comment-fenced block. Re-runs replace the block in place
# (never duplicate it); any Codex config the user added outside the fence is
# preserved. The block is appended at end-of-file on first write and stays
# there, so the [mcp_servers.*] tables never absorb unrelated keys. TOML
# double-quoted strings are literal — the github $(gh auth token) is expanded
# at launch by `sh -c`, exactly as in the JSON configs.
_mcp_write_codex_fmt() {
    local dest="$1" server_path="$2"
    local start="# >>> ai-dev-envbuild MCP servers (managed — do not edit) >>>"
    local end="# <<< ai-dev-envbuild MCP servers (managed — do not edit) <<<"
    ensure_dir "$(dirname "$dest")"
    [ -f "$dest" ] || : > "$dest"
    backup_file "$dest"
    local bf tmp; bf="$(mktemp)"; tmp="$(mktemp)"
    {
        printf '[mcp_servers.devenv]\ncommand = "node"\nargs = ["%s"]\n\n' "$server_path"
        printf '[mcp_servers.github]\ncommand = "sh"\nargs = ["-c", "GITHUB_TOKEN=$(gh auth token) npx -y @modelcontextprotocol/server-github"]\n\n'
        printf '[mcp_servers.playwright]\ncommand = "npx"\nargs = ["-y", "@playwright/mcp"]\n\n'
        printf '[mcp_servers.context7]\ncommand = "npx"\nargs = ["-y", "@upstash/context7-mcp"]\n\n'
        printf '[mcp_servers.ollama]\ncommand = "npx"\nargs = ["-y", "@modelcontextprotocol/server-ollama"]\n'
    } > "$bf"
    if grep -qF "$start" "$dest"; then
        awk -v s="$start" -v e="$end" -v bf="$bf" '
            $0==s { print; while ((getline l < bf) > 0) print l; close(bf); inblk=1; next }
            $0==e { inblk=0; print; next }
            inblk!=1 { print }
        ' "$dest" > "$tmp"
    else
        { cat "$dest"; printf '\n%s\n' "$start"; cat "$bf"; printf '%s\n' "$end"; } > "$tmp"
    fi
    mv "$tmp" "$dest"; rm -f "$bf"
}

mcp_register() {
    if is_dry_run; then log_info "[DRY-RUN] would register MCP servers for Claude Code, Codex, VS Code, and Cursor"; return 0; fi
    local server_path="$REPO_ROOT/mcp-server/index.js"

    # ── Claude Code (USER scope → loads in every project, no approval) ──────────
    _mcp_write_claude_fmt "$HOME/.claude.json" "$server_path"
    log_ok "Claude Code  → ~/.claude.json (user scope — loads by default)"

    # ── Codex (reads ~/.codex/config.toml unconditionally) ──────────────────────
    if [ -d "$HOME/.codex" ] || has codex; then
        _mcp_write_codex_fmt "$HOME/.codex/config.toml" "$server_path"
        log_ok "Codex        → ~/.codex/config.toml"
    else
        log_info "mcp: Codex not detected (no ~/.codex) — skipping"
    fi

    # ── VS Code + Cursor (Windows AppData, WSL2 only) ─────────────────────────
    local appdata; appdata="$(_mcp_win_appdata)"
    if [ -z "$appdata" ]; then
        log_info "mcp: not a WSL2 environment or cmd.exe unavailable — skipping VS Code/Cursor"
        log_info "restart Claude Code / Codex to load the new MCP tools"
        return 0
    fi

    local vscode_user="$appdata/Code/User"
    if [ -d "$vscode_user" ]; then
        _mcp_write_vscode_fmt "$vscode_user/mcp.json" "$server_path"
        log_ok "VS Code      → $vscode_user/mcp.json"
    else
        log_info "mcp: VS Code user dir not found — skipping ($vscode_user)"
    fi

    local cursor_user="$appdata/Cursor/User"
    if [ -d "$cursor_user" ]; then
        _mcp_write_vscode_fmt "$cursor_user/mcp.json" "$server_path"
        log_ok "Cursor       → $cursor_user/mcp.json"
    else
        log_info "mcp: Cursor not installed — skipping (install Cursor to auto-register)"
    fi

    log_info "restart Claude Code / Codex / VS Code / Cursor to load the new MCP tools"
}

mcp_register_agent_coding() {
    if is_dry_run; then
        log_info "[DRY-RUN] would register agent-coding MCP server (ollama)"
        return 0
    fi
    if ! command -v ollama >/dev/null 2>&1; then
        log_info "mcp: ollama not installed (agent-coding not run) — skipping ollama MCP registration"
        return 0
    fi

    local server_path="$REPO_ROOT/mcp-server/index.js"

    _mcp_write_claude_fmt "$HOME/.claude.json" "$server_path"
    log_ok "Claude Code  → ollama MCP registered"

    if [ -d "$HOME/.codex" ] || has codex; then
        _mcp_write_codex_fmt "$HOME/.codex/config.toml" "$server_path"
        log_ok "Codex        → ollama MCP registered"
    fi

    local appdata; appdata="$(_mcp_win_appdata)"
    if [ -n "$appdata" ]; then
        local vscode_user="$appdata/Code/User"
        [ -d "$vscode_user" ] && _mcp_write_vscode_fmt "$vscode_user/mcp.json" "$server_path"

        local cursor_user="$appdata/Cursor/User"
        [ -d "$cursor_user" ] && _mcp_write_vscode_fmt "$cursor_user/mcp.json" "$server_path"
    fi

    log_info "ollama MCP registered — restart your agent to load it"
}
