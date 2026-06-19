#!/usr/bin/env bash
# agent-coding — local AI coding agent stack: Ollama daemon + coder model + aider CLI.
# Opt in with: ./bootstrap.sh --with agent-coding
#
# Per the architecture, Ollama is a system runtime (always-on daemon, cross-project),
# so it lives at the system layer. The ML projects themselves (uv venvs, PyTorch, etc.)
# stay project-local per the global-vs-project boundary. Aider is a global CLI tool
# (pipx) — invoked by name from any project, does not import into a project venv.

agent_coding_desc() { echo "Ollama + VRAM-aware coder model + aider + Continue ext — local agent coding stack (requires --with)"; }

agent_coding_install() {
    local vram_mb=0
    if has nvidia-smi; then
        vram_mb="$(agent_coding_gpu_vram_mb)"
        log_ok "GPU detected (total VRAM: ${vram_mb} MB)"
        nvidia-smi -L 2>/dev/null | sed 's/^/    /'
    else
        log_warn "no NVIDIA GPU detected — agent-coding group works on CPU but very slow"
    fi

    agent_coding_ollama
    agent_coding_ollama_service
    agent_coding_aider
    agent_coding_vscode_extension
    agent_coding_pull_model "$vram_mb"
    agent_coding_record_manifest "$vram_mb"

    cat <<GUIDE

agent-coding setup complete.

  Start the daemon (runs in background, ~0 VRAM idle):
    ollama serve

  Selected model for ${vram_mb} MB VRAM:
    $(agent_coding_model_name "$vram_mb")
  Pull it (first request auto-pulls, or pre-pull):
    ollama pull $(agent_coding_model_tag "$vram_mb")

  Pair-program with aider:
    aider --model ollama/$(agent_coding_model_tag "$vram_mb")

  VS Code: Continue extension installed — open the Continue sidebar
  and set your provider to Ollama (http://localhost:11434).

  Auto-start on WSL boot (already installed as user systemd unit):
    systemctl --user enable --now ollama

GUIDE
}

# Detect total GPU VRAM in MB. Returns 0 if nvidia-smi fails.
agent_coding_gpu_vram_mb() {
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
        | head -1 | tr -d ' ' || echo 0
}

# Given VRAM in MB, pick the largest model that fits.
# Ollama tag format: qwen2.5vl:<size>b (no dash, no -instruct suffix)
# Vision models need extra VRAM for the multimodal projector (CLIP + projector +
# vision encoder). After real-world testing, 32B needs >24 GB even on a "free"
# 4090. Conservative tiers:
#   7B  ~6 GB  — fits 8 GB+ cards comfortably, best quality/size tradeoff
#   3B  ~3 GB  — fits 4 GB cards or when you need headroom for other models
agent_coding_model_tag() {
    local vram_mb="${1:-0}"
    if [ "$vram_mb" -ge 12000 ]; then
        echo "qwen2.5vl:7b"
    elif [ "$vram_mb" -ge 5000 ]; then
        echo "qwen2.5vl:3b"
    else
        echo "qwen2.5-coder:7b"
    fi
}

agent_coding_model_name() {
    local tag; tag="$(agent_coding_model_tag "$1")"
    case "$tag" in
        *32b*) echo "Qwen2.5-VL 32B (vision-coder, ~21 GB)" ;;
        *7b*)  echo "Qwen2.5-VL 7B (vision-coder, ~6 GB)" ;;
        *3b*)  echo "Qwen2.5-VL 3B (vision-coder, ~3 GB)" ;;
        *)     echo "Qwen2.5-Coder 7B (text-only, ~4 GB)" ;;
    esac
}

agent_coding_ollama() {
    if has ollama; then
        log_skip "ollama already installed ($(ollama --version 2>/dev/null | head -1))"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would install ollama"; return 0; fi
    log_info "installing ollama (upstream .deb)"
    local url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.deb"
    local deb; deb="$(mktemp --suffix=.deb)"
    if curl -fsSL "$url" -o "$deb"; then
        sudo dpkg -i "$deb" >/dev/null 2>&1 || sudo apt-get install -f -y
        log_ok "ollama installed"
    else
        log_err "ollama download failed — see https://ollama.com/download/linux"
        return 1
    fi
    rm -f "$deb"
}

agent_coding_ollama_service() {
    if is_dry_run; then log_info "[DRY-RUN] would install ollama user systemd service"; return 0; fi
    has ollama || { log_warn "ollama not installed — skipping service setup"; return 0; }

    local unit_dir="$HOME/.config/systemd/user"
    ensure_dir "$unit_dir"

    local unit="$unit_dir/ollama.service"
    if [ -f "$unit" ] && grep -q "ExecStart=ollama serve" "$unit" 2>/dev/null; then
        log_skip "ollama systemd unit already present"
        return 0
    fi

    cat > "$unit" <<'UNIT'
[Unit]
Description=Ollama local LLM daemon
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=ollama serve
Environment=HOME=%h

# Hardening (daemon needs socket access only)
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
UNIT

    chmod 644 "$unit"
    log_ok "ollama user systemd unit written -> $unit"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
        log_info "run 'systemctl --user enable --now ollama' to start the daemon"
    else
        log_info "systemctl not available — start ollama manually with: ollama serve"
    fi
}

agent_coding_aider() {
    if has aider; then
        log_skip "aider already installed ($(aider --version 2>/dev/null | head -1))"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would pipx install aider-chat"; return 0; fi
    pipx_install aider-chat
    log_ok "aider installed (pipx)"
}

# Install Continue (continue.dev) VS Code extension if the `code` CLI is available.
agent_coding_vscode_extension() {
    if is_dry_run; then log_info "[DRY-RUN] would install Continue VS Code extension"; return 0; fi
    if ! command -v code >/dev/null 2>&1; then
        log_info "VS Code CLI (code) not found — skipping Continue extension install"
        log_info "  Install manually: search 'Continue' in the VS Code Extensions marketplace"
        return 0
    fi
    if code --list-extensions 2>/dev/null | grep -qx "continue.continue"; then
        log_skip "Continue extension already installed"
        return 0
    fi
    log_info "installing Continue VS Code extension (continue.continue)"
    if code --install-extension continue.continue --force 2>/dev/null; then
        log_ok "Continue extension installed"
    else
        log_warn "Continue extension install failed — install manually from the marketplace"
    fi
}

# Pull the VRAM-appropriate model. Guarded: skips if already present.
# NOTE: not auto-pulled during bootstrap (19 GB download would hang the run).
# The daemon auto-pulls on first inference request; run manually to pre-cache.
agent_coding_pull_model() {
    local vram_mb="${1:-0}"
    local tag; tag="$(agent_coding_model_tag "$vram_mb")"
    local name; name="$(agent_coding_model_name "$vram_mb")"
    local size_gb; size_gb="$(agent_coding_model_size_gb "$tag")"

    if is_dry_run; then
        log_info "[DRY-RUN] would instruct: ollama pull $tag ($name, ~${size_gb} GB)"
        return 0
    fi
    has ollama || { log_warn "ollama not installed — skipping model instructions"; return 0; }

    if ollama list 2>/dev/null | grep -q "$tag"; then
        log_skip "model $tag already present ($name)"
        return 0
    fi

    log_info "VRAM-appropriate model for ${vram_mb} MB: $name ($tag, ~${size_gb} GB)"
    log_info "  Pull it now (one-time, or first request auto-pulls):"
    log_info "    ollama pull $tag"
}

# Rough size estimate for smoke-test display (not used for gating).
agent_coding_model_size_gb() {
    case "$1" in
        *32b*) echo "21" ;;
        *7b*)  echo "6"  ;;
        *3b*)  echo "3"  ;;
        *)     echo "4"  ;;
    esac
}

agent_coding_record_manifest() {
    local vram_mb="${1:-0}"

    if has ollama; then
        manifest_add ollama ollama agent-coding global apt \
            "ollama --version" optional \
            "Local LLM daemon (Ollama). System runtime: always-on service, ~0 VRAM idle. Models loaded on demand. GPU projects stay project-local."
    fi

    local tag; tag="$(agent_coding_model_tag "$vram_mb")"
    local name; name="$(agent_coding_model_name "$vram_mb")"

    if ollama list 2>/dev/null | grep -q "$tag"; then
        manifest_add "${tag}" ollama agent-coding container ollama \
            "ollama list | grep $tag" optional \
            "$name. Selected automatically for ${vram_mb} MB VRAM. LICENSE: Qwen (Apache 2.0). Change agent_coding_model_tag() in modules/agent-coding.sh to override."
    fi

    if has aider; then
        manifest_add aider aider agent-coding global pipx \
            "aider --version" optional \
            "CLI pair-programming agent. Native Ollama support: aider --model ollama/$tag"
    fi
}
