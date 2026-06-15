#!/usr/bin/env bash
# claude — Claude Code user settings for ~/.claude/settings.json and settings.local.json
#
# Writes/merges the correct model, effort, permission-mode, fast-mode, and
# thinking settings so every new Claude Code session starts with the right
# defaults. Existing permissions.allow rules and any other user-added keys
# are preserved — this module only sets the specific keys it owns.
#
# Two files are written:
#   settings.json       — primary user settings (effort, thinking, defaultMode, etc.)
#   settings.local.json — model + fastMode override; sits above remote-settings.json
#                         in load order so it beats enterprise policy model defaults.
#
# Re-running is fully idempotent.

claude_desc() { echo "Claude Code settings — model, effortLevel, defaultMode, fastMode, thinkingSummaries"; }

claude_install() {
    if is_dry_run; then log_info "[DRY-RUN] would write ~/.claude/settings.json and settings.local.json"; return 0; fi
    has node || { log_err "node not installed — run the node group first"; return 1; }

    local dest="$HOME/.claude/settings.json"
    ensure_dir "$(dirname "$dest")"
    [ -f "$dest" ] || printf '{}\n' > "$dest"
    backup_file "$dest"
    CLAUDE_SETTINGS="$dest" node --input-type=module <<'EOF'
import { readFileSync, writeFileSync } from "fs";
const dest = process.env.CLAUDE_SETTINGS;
const cfg = JSON.parse(readFileSync(dest, "utf8"));
// Owned keys — set unconditionally; all other keys in the file are untouched
cfg.model                 = "claude-opus-4-8";
cfg.effortLevel           = "high";
cfg.alwaysThinkingEnabled = true;
cfg.showThinkingSummaries = false;
cfg.fastMode              = true;
// Merge permissions — preserve allow/deny/ask rules, only set defaultMode
cfg.permissions             = cfg.permissions ?? {};
cfg.permissions.defaultMode = "auto";
writeFileSync(dest, JSON.stringify(cfg, null, 2) + "\n");
EOF
    log_ok "Claude Code  → $dest"
    log_ok "  effortLevel=high  fastMode=true  defaultMode=auto  showThinkingSummaries=false"

    # Write settings.local.json — this file loads after remote-settings.json and
    # overrides the enterprise-default model (Sonnet) with the user preference (Opus).
    local local_dest="$HOME/.claude/settings.local.json"
    [ -f "$local_dest" ] || printf '{}\n' > "$local_dest"
    backup_file "$local_dest"
    CLAUDE_LOCAL="$local_dest" node --input-type=module <<'EOF'
import { readFileSync, writeFileSync } from "fs";
const dest = process.env.CLAUDE_LOCAL;
let cfg = {};
try { cfg = JSON.parse(readFileSync(dest, "utf8")); } catch {}
cfg.model    = "claude-opus-4-8";
cfg.fastMode = true;
writeFileSync(dest, JSON.stringify(cfg, null, 2) + "\n");
EOF
    log_ok "Claude Code  → $local_dest (model=claude-opus-4-8 fastMode=true)"
    claude_record_manifest
}

claude_record_manifest() {
    manifest_add \
        "claude-settings" \
        "none" \
        "claude" \
        "user" \
        "config-file" \
        "jq -e '.fastMode == true' \$HOME/.claude/settings.json" \
        "active" \
        "~/.claude/settings.json — model/effort/fastMode/defaultMode/thinking defaults"
}
