#!/usr/bin/env bash
# optional-gpu — GPU / CUDA support. DETECTION + GUIDANCE only. Opt in with:
# ./bootstrap.sh --with optional-gpu
#
# Deliberately does NOT auto-install the multi-GB CUDA toolkit or GPU ML
# frameworks — per the architecture, GPU stays optional and heavy stacks are
# never installed by default. GPU work belongs in PROJECT environments
# (uv add torch ...) or CONTAINERS (NVIDIA Container Toolkit + `docker run
# --gpus`). This module reports what's available and prints the canonical setup
# paths so the choice and the cost stay explicit.

optional_gpu_desc() { echo "NVIDIA GPU: nvtop, nvidia-container-toolkit, iopaint (AI inpainting), RVRT video SR — detection + guidance"; }

optional_gpu_install() {
    if has nvidia-smi; then
        log_ok "GPU detected:"
        nvidia-smi -L 2>/dev/null | sed 's/^/    /'
        local driver vram_mb
        driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
        [ -n "$driver" ] && log_info "host driver: $driver"
        vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
        [ -z "$vram_mb" ] && vram_mb=0

        optional_gpu_nvtop
        optional_gpu_container_toolkit
        optional_gpu_nvcc

        cat <<'GUIDE'

GPU path summary:

  1. Containerized GPU (preferred for ML — installed above)
     docker run --rm --gpus all nvidia/cuda:12.6-base-ubuntu24.04 nvidia-smi
     Put PyTorch/TensorFlow in the container image, not the host.

  2. Native CUDA toolkit (only if you build CUDA C code on the host)
     Use NVIDIA's CUDA installer (on WSL, omits the display driver):
       https://developer.nvidia.com/cuda-downloads
     Project Python GPU libs still go in a project .venv via uv:
       uv add torch --index https://download.pytorch.org/whl/cu124

  3. Video super-resolution — RVRT / BasicVSR++ (project-local, GPU-accelerated)
     Temporal-aware upscaling: processes frame sequences, not individual frames.
     RVRT (Recurrent Video Restoration Transformer) is the recommended model.
     Setup in a project venv (uv), then re-run ./bootstrap.sh --only optional-gpu
     to register the weights in the manifest:
       cd ~/projects/<video-project>
       uv venv --python 3.11
       uv add torch torchvision --index https://download.pytorch.org/whl/cu132
       uv add timm einops tensorboard opencv-python scikit-image scipy ninja
       git clone https://github.com/JingyunLiang/RVRT
     Models auto-download to RVRT/model_zoo/rvrt/ on first inference run.
     Run inference: uv run python RVRT/main_test_rvrt.py --task 001_RVRT_videosr_bi_REDS_30frames \
       --folder_lq <input-frames-dir> --tile 100 128 128 --save_result

  4. Image-gen model checkpoints (large, optional, never auto-downloaded)
     Recorded in the manifest only when already present in the HF cache; this
     module never pulls weights itself. Fetch into a GPU project, then re-run
     ./bootstrap.sh --only optional-gpu to register them:
       cd <your-gpu-project>
       uv run hf download diffusers/stable-diffusion-xl-1.0-inpainting-0.1  # ~20 GB, OpenRAIL++
       uv run hf download black-forest-labs/FLUX.1-Fill-dev                 # ~55 GB, FLUX.1 [dev] NON-COMMERCIAL license
     Project-local model files (e.g. a RealESRGAN .pth in a project's models/
     dir) are NOT machine-wide — document those in the project's own MODELS.md,
     not here.

GUIDE

        optional_gpu_whisper_guide
        optional_gpu_anime_guide "$vram_mb"

        if is_wsl; then
            manifest_add nvidia-smi nvidia-smi optional-gpu global windows-host-driver \
                "nvidia-smi -L" optional \
                "GPU available via Windows host driver passthrough; CUDA toolkit/ML libs are project/container scoped"
        else
            manifest_add nvidia-smi nvidia-smi optional-gpu global apt \
                "nvidia-smi -L" optional \
                "GPU available via local NVIDIA driver; CUDA toolkit/ML libs are project/container scoped"
        fi
        if has nvtop; then
            manifest_add nvtop nvtop optional-gpu global apt \
                "nvtop --version" optional "GPU process monitor (htop for NVIDIA)"
        fi
        if pkg_installed nvidia-container-toolkit; then
            manifest_add nvidia-container-toolkit nvidia-ctk optional-gpu global apt \
                "nvidia-ctk --version" optional \
                "enables docker run --gpus all; runtime configured via nvidia-ctk"
        fi
    else
        if is_wsl; then
            log_warn "no nvidia-smi — no GPU passthrough detected."
            log_info "To enable: install the NVIDIA driver on the Windows host (the WSL CUDA stack rides on it — do NOT install a Linux NVIDIA driver inside WSL), then restart WSL."
        else
            log_warn "no nvidia-smi — NVIDIA GPU driver not installed."
            log_info "To enable: install the NVIDIA driver from https://www.nvidia.com/Download/index.aspx or via your distro's package manager."
        fi
    fi

    _optional_gpu_record_sdxl_inpaint
    _optional_gpu_record_flux_dev
    _optional_gpu_record_flux_fill
    _optional_gpu_record_wan_t2v
    _optional_gpu_record_wan_i2v
    _optional_gpu_record_rvrt
    _optional_gpu_record_anime_sd15
    _optional_gpu_record_anime_xl
    log_ok "manifest updated — optional-gpu group"
}

optional_gpu_nvtop() {
    apt_install nvtop
}

# cuda-nvcc-13-1 — CUDA compiler for JIT-compiling project CUDA C++ extensions
# (e.g. RVRT deform_attn). Installs to /usr/local/cuda-13.1/bin/nvcc (not on
# PATH by default). Symlinked into ~/tools/bin so it's accessible from shell.
# Set CUDA_HOME=/usr/local/cuda-13.1 when building torch cpp_extensions.
optional_gpu_nvcc() {
    local nvcc_bin="/usr/local/cuda-13.1/bin/nvcc"
    if [ ! -x "$nvcc_bin" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would apt install cuda-nvcc-13-1 (requires CUDA apt repo)"; return 0; fi
        # cuda-nvcc-13-1 lives in the NVIDIA CUDA apt repository, not standard Ubuntu.
        # If the repo isn't configured, warn and skip rather than aborting the whole bootstrap.
        if ! apt-cache show cuda-nvcc-13-1 >/dev/null 2>&1; then
            log_warn "cuda-nvcc-13-1 not in apt index — add the CUDA apt repo first:"
            log_info "  wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb"
            log_info "  sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update"
            log_info "  Then re-run: ./bootstrap.sh --only optional-gpu"
            return 0
        fi
        apt_install cuda-nvcc-13-1
    fi
    if [ -x "$nvcc_bin" ]; then
        ln -sf "$nvcc_bin" "$HOME/tools/bin/nvcc"
        log_ok "nvcc -> $nvcc_bin (symlinked to ~/tools/bin/nvcc)"
        manifest_add cuda-nvcc nvcc optional-gpu global apt \
            "nvcc --version" optional \
            "CUDA compiler 13.1 at /usr/local/cuda-13.1/bin/nvcc; symlinked to ~/tools/bin/nvcc. Use CUDA_HOME=/usr/local/cuda-13.1 when building torch cpp_extensions (e.g. RVRT deform_attn). Installed only when GPU present."
    else
        log_err "cuda-nvcc-13-1 install failed — nvcc not found at $nvcc_bin"
    fi
}

optional_gpu_container_toolkit() {
    if pkg_installed nvidia-container-toolkit; then
        log_skip "nvidia-container-toolkit already installed"
        return 0
    fi
    if is_dry_run; then
        log_info "[DRY-RUN] would install nvidia-container-toolkit"
        return 0
    fi
    local keyring="/etc/apt/keyrings/nvidia-container-toolkit.gpg"
    sudo install -m 0755 -d /etc/apt/keyrings
    log_info "adding NVIDIA container toolkit apt repo"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o "$keyring"
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed "s#deb https://#deb [signed-by=$keyring] https://#g" \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
    _APT_UPDATED=0
    apt_install nvidia-container-toolkit
    if has docker && docker info >/dev/null 2>&1; then
        sudo nvidia-ctk runtime configure --runtime=docker
        log_ok "docker configured for GPU (nvidia runtime)"
    else
        log_info "docker not running — after starting Docker, run: sudo nvidia-ctk runtime configure --runtime=docker"
    fi
}

_optional_gpu_record_sdxl_inpaint() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--diffusers--stable-diffusion-xl-1.0-inpainting-0.1"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would record sdxl-inpaint checkpoint"; return 0; fi
        # Write a presence-check shim so devtools check (command -v) and
        # smoke-test can both verify the checkpoint with a real binary.
        local shim="$HOME/tools/bin/sdxl-inpaint"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add sdxl-inpaint-checkpoint sdxl-inpaint optional-gpu container huggingface \
            "sdxl-inpaint" optional \
            "SDXL inpainting checkpoint (~20 GB on disk: fp16+fp32 variants cached; 9-ch UNet); clean mask seams vs standard inpainting. License: OpenRAIL++. Canonical: containerized GPU. Exception: if a GPU project venv exists, run from there instead. Download: cd <your-gpu-project> && uv run hf download diffusers/stable-diffusion-xl-1.0-inpainting-0.1"
    fi
}

# RVRT — Recurrent Video Restoration Transformer. Project-local video SR model.
# Recorded only when the pretrained weights are present in a known project
# (~/projects/ai-helper/RVRT). Re-run ./bootstrap.sh --only optional-gpu after
# setting up the venv and downloading weights to register the manifest entry.
_optional_gpu_record_rvrt() {
    local rvrt_dir="$HOME/projects/ai-helper/RVRT/model_zoo/rvrt"
    if [ -d "$rvrt_dir" ] && compgen -G "$rvrt_dir/*.pth" > /dev/null 2>&1; then
        if is_dry_run; then log_info "[DRY-RUN] would write rvrt-video shim"; return 0; fi
        local shim="$HOME/tools/bin/rvrt-video"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$rvrt_dir"
SHIM
        chmod +x "$shim"
        manifest_add rvrt-video rvrt-video optional-gpu project github \
            "rvrt-video" optional \
            "RVRT (Recurrent Video Restoration Transformer) — temporal-aware 4x video SR. Project-local in ~/projects/ai-helper/RVRT. Models in model_zoo/rvrt/ (auto-downloaded on first run). Run: cd ~/projects/ai-helper && uv run python RVRT/main_test_rvrt.py --task 001_RVRT_videosr_bi_REDS_30frames --folder_lq <frames-dir> --tile 100 128 128 --save_result. Setup: uv add torch torchvision --index https://download.pytorch.org/whl/cu132 && uv add timm einops tensorboard opencv-python scikit-image scipy ninja"
    fi
}

# FLUX.1-dev — base text-to-image checkpoint (not inpaint). Recorded only when
# already in the HF cache. Used by wallpaper-imagegen/flux_generate.py.
# NON-COMMERCIAL license — personal wallpaper use is fine.
_optional_gpu_record_flux_dev() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--black-forest-labs--FLUX.1-dev"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would record flux-dev checkpoint"; return 0; fi
        local shim="$HOME/tools/bin/flux-dev"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add flux-dev-checkpoint flux-dev optional-gpu container huggingface \
            "flux-dev" optional \
            "FLUX.1-dev base text-to-image checkpoint (~23 GB; NF4 fits 24 GB VRAM). Used by wallpaper-imagegen/flux_generate.py. LICENSE: FLUX.1 [dev] NON-COMMERCIAL. Download: cd ~/projects/wallpaper-imagegen && uv run hf download black-forest-labs/FLUX.1-dev"
    fi
}

# FLUX.1-Fill-dev — large text-to-image inpaint/outpaint checkpoint. Recorded
# only when already present in the HF cache (this module never downloads the
# ~55 GB of weights). Mirrors the SDXL recorder: a presence-check shim lets
# devtools check / smoke-test verify it with a real binary. NOTE: FLUX.1 [dev]
# is under a NON-COMMERCIAL license — flagged in the manifest note.
_optional_gpu_record_flux_fill() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--black-forest-labs--FLUX.1-Fill-dev"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would write flux-fill-dev checkpoint presence shim"; return 0; fi
        local shim="$HOME/tools/bin/flux-fill-dev"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add flux-fill-dev-checkpoint flux-fill-dev optional-gpu container huggingface \
            "flux-fill-dev" optional \
            "FLUX.1-Fill-dev inpaint/outpaint checkpoint (~55 GB on disk: transformer + T5/CLIP text encoders + VAE). 4-bit NF4 quant fits ~24 GB VRAM. LICENSE: FLUX.1 [dev] NON-COMMERCIAL. Canonical: containerized GPU. Exception: if a GPU project venv exists, run from there instead. Download: cd <your-gpu-project> && uv run hf download black-forest-labs/FLUX.1-Fill-dev"
    fi
}

# Wan2.1-T2V-14B — text-to-video checkpoint. Recorded only when already in the
# HF cache (never auto-downloaded by this module). Apache 2.0 — no restrictions.
_optional_gpu_record_wan_t2v() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--Wan-AI--Wan2.1-T2V-14B-Diffusers"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would record wan-t2v checkpoint"; return 0; fi
        local shim="$HOME/tools/bin/wan-t2v"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add wan-t2v-checkpoint wan-t2v optional-gpu container huggingface \
            "wan-t2v" optional \
            "Wan2.1-T2V-14B text-to-video checkpoint (~28 GB bfloat16, ~10 GB NF4). Used by wallpaper-imagegen/wan_generate.py t2v. LICENSE: Apache 2.0. Download: hf download Wan-AI/Wan2.1-T2V-14B-Diffusers"
    fi
}

# Wan2.1-I2V-14B-480P — image-to-video checkpoint. Recorded only when already
# in the HF cache (never auto-downloaded). Apache 2.0 — no restrictions.
_optional_gpu_record_wan_i2v() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--Wan-AI--Wan2.1-I2V-14B-480P-Diffusers"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would record wan-i2v checkpoint"; return 0; fi
        local shim="$HOME/tools/bin/wan-i2v"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add wan-i2v-checkpoint wan-i2v optional-gpu container huggingface \
            "wan-i2v" optional \
            "Wan2.1-I2V-14B-480P image-to-video checkpoint (~28 GB bfloat16, ~10 GB NF4). Used by wallpaper-imagegen/wan_generate.py i2v. LICENSE: Apache 2.0. Download: hf download Wan-AI/Wan2.1-I2V-14B-480P-Diffusers"
    fi
}

# VRAM-aware guide for anime generation model downloads. Called from
# optional_gpu_install() when a GPU is present. Presence recorders below
# pick them up once cached; re-run ./bootstrap.sh --only optional-gpu to register.
# faster-whisper is deployed as a project service on Elsewhere (not the local
# machine), so this module only documents the setup — no local install is done.
optional_gpu_whisper_guide() {
    log_info "faster-whisper transcription service (Elsewhere GPU — ~/faster-whisper-svc/):"
    log_info "  Model : large-v3 (float16, CUDA) — ~30-40× realtime on RTX 4090"
    log_info "  Port  : 8990 (systemd faster-whisper.service, auto-starts on boot)"
    log_info "  Tunnel: open via slide2html/start-kb.sh (SSH -L 8990:localhost:8990 elsewhere)"
    log_info "  Deps  : faster-whisper fastapi uvicorn python-multipart (pip, in ~/faster-whisper-svc/venv)"
    log_info "          LD_LIBRARY_PATH=/usr/local/lib/ollama/cuda_v12 set in the systemd unit"
    log_info "  Use   : drop A/V files in slide2html/intake/ then uv run intake.py --auto"
}

optional_gpu_anime_guide() {
    local vram_mb="${1:-0}"
    log_info "anime generation models (VRAM-tiered; download then re-run --only optional-gpu to register):"
    if [ "$vram_mb" -ge 6000 ]; then
        log_info "  8+ GB  : hf download hakurei/waifu-diffusion          (~4 GB  SD1.5  Apache 2.0)"
    fi
    if [ "$vram_mb" -ge 12000 ]; then
        log_info "  12+ GB : hf download cagliostrolab/animagine-xl-3.1   (~7 GB  SDXL   Apache 2.0)"
    fi
    if [ "$vram_mb" -lt 6000 ]; then
        log_warn "  < 6 GB VRAM detected (${vram_mb} MB) — anime generation models require >= 6 GB VRAM"
    fi
}

# waifu-diffusion — SD1.5 anime image generation. Recorded only when already in
# the HF cache with actual model weights (blobs > 100 MB). Apache 2.0.
# Download: hf download hakurei/waifu-diffusion
_optional_gpu_record_anime_sd15() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--hakurei--waifu-diffusion"
    if [ -d "$hf_dir" ] && find "$hf_dir/blobs" -type f -size +100M -maxdepth 1 2>/dev/null | grep -q .; then
        if is_dry_run; then log_info "[DRY-RUN] would record waifu-diffusion checkpoint"; return 0; fi
        local shim="$HOME/tools/bin/waifu-diffusion"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add waifu-diffusion-checkpoint waifu-diffusion optional-gpu container huggingface \
            "waifu-diffusion" optional \
            "waifu-diffusion SD1.5 anime generation (~4 GB; 8 GB VRAM). Works with iopaint (--model sd1.5) and standard diffusers pipelines. LICENSE: Apache 2.0. Download: hf download hakurei/waifu-diffusion"
    fi
}

# animagine-xl-3.1 — SDXL high-quality anime generation. Recorded only when
# already in the HF cache with actual model weights (blobs > 100 MB). Apache 2.0.
# Needs 12+ GB VRAM (~7 GB weights); comfortable on 24 GB.
# Download: hf download cagliostrolab/animagine-xl-3.1
_optional_gpu_record_anime_xl() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--cagliostrolab--animagine-xl-3.1"
    if [ -d "$hf_dir" ] && find "$hf_dir/blobs" -type f -size +100M -maxdepth 1 2>/dev/null | grep -q .; then
        if is_dry_run; then log_info "[DRY-RUN] would record animagine-xl-3.1 checkpoint"; return 0; fi
        local shim="$HOME/tools/bin/animagine-xl"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add animagine-xl-checkpoint animagine-xl optional-gpu container huggingface \
            "animagine-xl" optional \
            "Animagine XL 3.1 SDXL anime generation (~7 GB; 12+ GB VRAM, comfortable on 24 GB). Standard diffusers SDXL pipeline. LICENSE: Apache 2.0. Download: hf download cagliostrolab/animagine-xl-3.1"
    fi
}
