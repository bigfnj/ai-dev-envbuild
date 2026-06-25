#!/usr/bin/env bash
# agent-coding — local AI coding agent stack: Ollama daemon + coder model + aider CLI.
# Opt in with: ./bootstrap.sh --with agent-coding
#
# Per the architecture, Ollama is a system runtime (always-on daemon, cross-project),
# so it lives at the system layer. The ML projects themselves (uv venvs, PyTorch, etc.)
# stay project-local per the global-vs-project boundary. Aider is a global CLI tool
# (pipx) — invoked by name from any project, does not import into a project venv.

agent_coding_desc() { echo "Ollama + VRAM-aware model fleet + aider + Continue ext — local agent coding stack (requires --with)"; }

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

    local primary; primary="$(agent_coding_model_tag "$vram_mb")"
    cat <<GUIDE

agent-coding setup complete.

  Start the daemon (runs in background, ~0 VRAM idle):
    ollama serve

  Model fleet that fits ${vram_mb} MB VRAM (loaded on demand, one at a time):
$(agent_coding_fleet_fits "$vram_mb" | while read -r t; do printf '    %-34s %s\n' "$t" "$(agent_coding_model_name_for_tag "$t")"; done)

  Default for aider/Continue (jack-of-all-trades that fits):  ollama/$primary

  Pre-pull the fleet (first request also auto-pulls):
$(agent_coding_fleet_fits "$vram_mb" | while read -r t; do printf '    ollama pull %s\n' "$t"; done)

  Pair-program with aider:
    aider --model ollama/$primary

  VS Code: Continue extension installed — open the Continue sidebar
  and set your provider to Ollama (http://localhost:11434).

  Auto-start on boot (system service, installed by the ollama .deb):
    sudo systemctl enable --now ollama

GUIDE
}

# Detect total GPU VRAM in MB. Returns 0 if nvidia-smi fails.
agent_coding_gpu_vram_mb() {
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
        | head -1 | tr -d ' ' || echo 0
}

# The agent-coding model fleet — a "barbell": tiny always-resident specialists
# (FIM autocomplete + embeddings) + one default generalist + heavier models
# loaded on demand. One pipe-delimited record per model:
#   tag | role | approx_gb | min_vram_mb | capabilities | human name
# Roles: generalist/coder/vision/reasoning = chat models; autocomplete = FIM;
# embed = codebase RAG. Capability "tools" = structured tool-calling VERIFIED via
# Ollama; qwen2.5-coder emits tool calls as inline JSON Ollama does NOT parse, so
# it's "code" (chat/edit), not an Agent-mode tool-caller.
# min_vram_mb = weights + KV (+ vision projector). Big models load one at a time.
# WSL2/WDDM caps a single cudaMalloc at ~ (free VRAM − 4.5 GB), so the ~18 GB 30B
# models need ~23 GB free to load full-GPU and can OOM under desktop load — hence
# they're load-on-demand, with mistral/qwen3-vl as the always-fits defaults.
# Tags verified against the registry — the thinking build ships only quant-
# suffixed tags (no bare :30b-a3b-thinking-2507; ollama pull exits 0 on a miss).
agent_coding_fleet() {
    cat <<'FLEET'
mistral-small3.2:24b|generalist|15|18000|tools,vision|Mistral Small 3.2 24B (default — vision + structured tools)
qwen2.5-coder:14b|coder|9|11000|code|Qwen2.5-Coder 14B (fast chat/edit; tool calls not Ollama-parsed)
qwen3-vl:4b|vision|3|4000|tools,vision,thinking|Qwen3-VL 4B (vision + tools + thinking; fits 8 GB VRAM fully on GPU)
qwen3-coder:30b|coder-agent|18|22000|tools|Qwen3-Coder 30B-A3B (best agentic coder; load-on-demand)
qwen3:30b-a3b-thinking-2507-q4_K_M|reasoning|19|22000|tools,thinking|Qwen3 30B-A3B Thinking (reasoning + code; load-on-demand)
qwen2.5-coder:1.5b-base|autocomplete|1|2000|insert|Qwen2.5-Coder 1.5B Base (FIM autocomplete; always-resident)
mxbai-embed-large|embed|1|1000|embed|mxbai-embed-large (codebase embeddings; always-resident)
FLEET
}

# Fleet tags whose min_vram_mb <= available VRAM (largest first).
agent_coding_fleet_fits() {
    local vram_mb="${1:-0}"
    agent_coding_fleet | while IFS='|' read -r tag role gb minv caps name; do
        [ -n "$tag" ] && [ "$vram_mb" -ge "$minv" ] && echo "$tag"
    done
}

# One field of a fleet record by tag. $2 = field index (2=role 3=gb 4=min 5=caps 6=name).
agent_coding_fleet_field() {
    agent_coding_fleet | awk -F'|' -v t="$1" -v f="$2" '$1==t{print $f; exit}'
}

# Human name for a tag (falls back to the tag itself if not in the fleet).
agent_coding_model_name_for_tag() {
    local n; n="$(agent_coding_fleet_field "$1" 6)"
    [ -n "$n" ] && echo "$n" || echo "$1"
}

# Default (primary) model for a given VRAM: the best tool-capable *generalist*
# that fits full-GPU — a jack-of-all-trades. NOT the VRAM-tight 30B (load-on-
# demand) and NOT the coder (qwen2.5-coder's tool calls aren't Ollama-parsed).
#   >=18 GB  mistral-small3.2:24b  (15 GB — vision + structured tools, full-GPU)
#   >= 8 GB  qwen3-vl:8b           (6 GB — vision + tools + thinking)
#    < 8 GB  qwen3-vl:8b           (best effort; offloads to CPU and runs slow)
agent_coding_model_tag() {
    local vram_mb="${1:-0}"
    if   [ "$vram_mb" -ge 18000 ]; then echo "mistral-small3.2:24b"
    elif [ "$vram_mb" -ge 4000 ];  then echo "qwen3-vl:4b"
    else                                 echo "qwen3-vl:4b"
    fi
}

# Human name of the primary model for a given VRAM (used by GUIDE/manifest).
agent_coding_model_name() {
    agent_coding_model_name_for_tag "$(agent_coding_model_tag "$1")"
}

agent_coding_ollama() {
    if has ollama; then
        log_skip "ollama already installed ($(ollama --version 2>/dev/null | head -1))"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would install ollama (tar.zst)"; return 0; fi

    # zstd required for extraction (Ollama dropped the .deb in favour of tar.zst)
    apt_install zstd

    log_info "installing ollama (tar.zst, latest release)"
    local url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst"
    local tmp; tmp="$(mktemp --suffix=.tar.zst)"
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        log_err "ollama download failed — see https://ollama.com/download/linux"
        return 1
    fi
    sudo tar -I zstd -xf "$tmp" -C /usr/local
    rm -f "$tmp"

    # Create system user + groups (what the old .deb post-install script did)
    if ! id ollama >/dev/null 2>&1; then
        sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    fi
    getent group render >/dev/null 2>&1 && sudo usermod -a -G render ollama || true
    getent group video  >/dev/null 2>&1 && sudo usermod -a -G video  ollama || true

    # Write systemd unit (also handled by the old .deb)
    sudo tee /etc/systemd/system/ollama.service >/dev/null <<'UNIT'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="HOME=/usr/share/ollama"

[Install]
WantedBy=default.target
UNIT
    sudo systemctl daemon-reload 2>/dev/null || true
    log_ok "ollama installed → /usr/local/bin/ollama"
}

# Ensure the daemon runs as the .deb-provided SYSTEM service (User=ollama, models in
# /usr/share/ollama/.ollama/models). The ollama .deb installs and enables this unit,
# so we just make sure it's enabled+started. We deliberately do NOT add a per-user
# unit: two enabled services racing for :11434 is a real bug — after a reboot the
# system unit wins the port and you silently serve the wrong model store.
agent_coding_ollama_service() {
    if is_dry_run; then log_info "[DRY-RUN] would ensure system ollama.service is enabled+started"; return 0; fi
    has ollama || { log_warn "ollama not installed — skipping service setup"; return 0; }

    # Remove any legacy per-user unit written by earlier versions of this module,
    # so it can't race the system service for the port.
    local legacy="$HOME/.config/systemd/user/ollama.service"
    if [ -f "$legacy" ]; then
        systemctl --user disable --now ollama 2>/dev/null || true
        rm -f "$legacy"
        rm -rf "$HOME/.config/systemd/user/ollama.service.d"
        systemctl --user daemon-reload 2>/dev/null || true
        log_ok "removed legacy per-user ollama unit (system service is canonical)"
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        log_info "systemctl not available — start ollama manually with: ollama serve"
        return 0
    fi

    if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
        if sudo systemctl enable --now ollama 2>/dev/null; then
            log_ok "system ollama.service enabled + started (User=ollama, :11434)"
        else
            log_warn "could not enable system ollama.service — check: systemctl status ollama"
        fi
    else
        log_warn "system ollama.service not found — the ollama .deb normally installs it; start manually: ollama serve"
    fi

    agent_coding_ollama_gpu_rescue
}

# Durable cold-boot GPU fix (WSL2). On a fresh boot the first full CUDA *context* creation
# through the dxg paravirt layer takes >30s, which exceeds ollama's hardcoded 30s
# GPU-discovery watchdog — so the daemon registers CPU-ONLY and serves every model from
# CPU for the life of the process (fleet-wide ~15x slowdown until the next restart).
#
# An earlier attempt (an ExecStartPre that warmed cuInit) proved INSUFFICIENT: cuInit is
# cheap (~2s even cold) and does not warm the context-creation path that actually hangs.
# Instead we install a post-boot oneshot that, only if ollama came up CPU-only, creates a
# real CUDA context (the slow op, no watchdog) to warm the path and then restarts ollama —
# a warm-system restart reliably registers the GPU. Idempotent: no-op if already on GPU.
agent_coding_ollama_gpu_rescue() {
    if is_dry_run; then log_info "[DRY-RUN] would install ollama-gpu-rescue post-boot unit"; return 0; fi
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl list-unit-files ollama.service >/dev/null 2>&1 || return 0

    # Retire the earlier, ineffective cuInit ExecStartPre warm if present.
    if [ -f /etc/systemd/system/ollama.service.d/10-gpu-warm.conf ]; then
        sudo rm -f /etc/systemd/system/ollama.service.d/10-gpu-warm.conf /usr/local/bin/ollama-gpu-warm
        sudo rmdir /etc/systemd/system/ollama.service.d 2>/dev/null || true
        log_info "removed obsolete ollama GPU-warm ExecStartPre drop-in"
    fi

    has nvidia-smi || { log_info "no GPU — skipping ollama-gpu-rescue"; return 0; }

    sudo tee /usr/local/bin/ollama-gpu-rescue >/dev/null <<'RESCUE'
#!/usr/bin/env bash
# Post-boot rescue for ollama's WSL2 cold-boot GPU-discovery timeout.
# If ollama registered CPU-only this boot (first CUDA context creation exceeded its 30s
# discovery watchdog), create a real CUDA context here to warm the path, then restart
# ollama once so discovery re-runs hot. Idempotent: no-op if ollama already has the GPU.
set -u
log() { logger -t ollama-gpu-rescue "$*"; echo "ollama-gpu-rescue: $*"; }

verdict=""
for _ in $(seq 1 30); do
    verdict="$(journalctl -u ollama --no-pager -b 2>/dev/null | grep 'inference compute' | tail -1)"
    [ -n "$verdict" ] && break
    sleep 3
done
case "$verdict" in
    *"library=CUDA"*) log "ollama already on GPU — nothing to do"; exit 0 ;;
esac
log "ollama is CPU-only (or no verdict) — warming CUDA context + restarting"

/usr/bin/python3 - <<'PY' 2>/dev/null || true
import ctypes, time, sys
try:
    cuda = ctypes.CDLL("/usr/lib/wsl/lib/libcuda.so.1")
except Exception:
    sys.exit(0)
end = time.time() + 180
while time.time() < end:
    try:
        if cuda.cuInit(0) == 0:
            dev = ctypes.c_int(0)
            if cuda.cuDeviceGet(ctypes.byref(dev), 0) == 0:
                ctx = ctypes.c_void_p()
                if cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev) == 0:
                    ptr = ctypes.c_void_p()
                    cuda.cuMemAlloc_v2(ctypes.byref(ptr), 4096)
                    cuda.cuMemFree_v2(ptr)
                    cuda.cuCtxDestroy_v2(ctx)
                    sys.exit(0)
    except Exception:
        pass
    time.sleep(2)
sys.exit(1)
PY

systemctl restart ollama
log "restarted ollama; discovery will re-run on the warmed path"
exit 0
RESCUE
    sudo chmod 0755 /usr/local/bin/ollama-gpu-rescue

    sudo tee /etc/systemd/system/ollama-gpu-rescue.service >/dev/null <<'UNIT'
[Unit]
Description=Rescue ollama GPU discovery after WSL2 cold boot
After=ollama.service
Wants=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ollama-gpu-rescue

[Install]
WantedBy=multi-user.target
UNIT
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable ollama-gpu-rescue.service 2>/dev/null || true
    log_ok "installed ollama-gpu-rescue post-boot unit (recovers cold-boot CPU-only fallback)"
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

# Report the fleet that fits this VRAM, flagging which models are already present.
# NOTE: not auto-pulled during bootstrap (tens of GB would hang the run).
# The daemon auto-pulls on first inference request; pre-pull to cache.
agent_coding_pull_model() {
    local vram_mb="${1:-0}" tag name gb

    if is_dry_run; then
        while IFS= read -r tag; do
            name="$(agent_coding_model_name_for_tag "$tag")"
            gb="$(agent_coding_fleet_field "$tag" 3)"
            log_info "[DRY-RUN] would instruct: ollama pull $tag ($name, ~${gb} GB)"
        done < <(agent_coding_fleet_fits "$vram_mb")
        return 0
    fi
    has ollama || { log_warn "ollama not installed — skipping model instructions"; return 0; }

    log_info "agent-coding model fleet for ${vram_mb} MB VRAM (loaded on demand, one at a time):"
    while IFS= read -r tag; do
        name="$(agent_coding_model_name_for_tag "$tag")"
        gb="$(agent_coding_fleet_field "$tag" 3)"
        if ollama list 2>/dev/null | grep -q "$tag"; then
            log_skip "  $tag present ($name)"
        else
            log_info "  $tag ($name, ~${gb} GB) — pull: ollama pull $tag"
        fi
    done < <(agent_coding_fleet_fits "$vram_mb")
}

agent_coding_record_manifest() {
    local vram_mb="${1:-0}" tag name caps note primary
    primary="$(agent_coding_model_tag "$vram_mb")"

    if has ollama; then
        manifest_add ollama ollama agent-coding global apt \
            "ollama --version" optional \
            "Local LLM daemon (Ollama). System runtime: always-on service, ~0 VRAM idle. Models loaded on demand. GPU projects stay project-local."
    fi

    # Register every fleet model that is actually pulled.
    while IFS= read -r tag; do
        ollama list 2>/dev/null | grep -q "$tag" || continue
        name="$(agent_coding_model_name_for_tag "$tag")"
        caps="$(agent_coding_fleet_field "$tag" 5)"
        note="$name. Capabilities: ${caps}. LICENSE: Apache 2.0."
        [ "$tag" = "$primary" ] && note="$note Default for aider/Continue at ${vram_mb} MB VRAM."
        note="$note Edit agent_coding_fleet() in modules/agent-coding.sh to change the fleet."
        manifest_add "$tag" ollama agent-coding container ollama \
            "ollama list | grep $tag" optional "$note"
    done < <(agent_coding_fleet_fits "$vram_mb")

    if has aider; then
        manifest_add aider aider agent-coding global pipx \
            "aider --version" optional \
            "CLI pair-programming agent. Native Ollama support: aider --model ollama/$primary"
    fi
}
