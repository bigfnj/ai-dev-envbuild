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

optional_gpu_desc() { echo "NVIDIA/CUDA detection + setup guidance (no heavy auto-install)"; }

optional_gpu_install() {
    if ! has nvidia-smi; then
        log_warn "no nvidia-smi — no GPU passthrough detected in this WSL."
        log_info "To enable: install the NVIDIA driver on the WINDOWS host (the WSL CUDA stack rides on it — do NOT install a Linux NVIDIA driver inside WSL), then restart WSL."
        return 0
    fi

    log_ok "GPU detected:"
    nvidia-smi -L 2>/dev/null | sed 's/^/    /'
    local cuda
    cuda="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
    [ -n "$cuda" ] && log_info "host driver: $cuda"

    cat <<'GUIDE'

GPU is available. Two recommended paths (pick per project — do not install
globally):

  1. Containerized GPU (preferred for ML — clean + reproducible)
     - Install the NVIDIA Container Toolkit:
         https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
     - Then: docker run --rm --gpus all <image> nvidia-smi
     - Put PyTorch/TensorFlow in the container image, not the host.

  2. Native CUDA toolkit (only if you build CUDA code on the host)
     - Use NVIDIA's WSL-Ubuntu/Debian CUDA repo (the "WSL" variant, which omits
       the Linux display driver): https://developer.nvidia.com/cuda-downloads
     - Project Python GPU libs still go in a project .venv via uv, e.g.:
         uv add torch --index https://download.pytorch.org/whl/cu124

  3. SDXL dedicated inpainting checkpoint (~7 GB, optional)
     stable-diffusion-xl-1.0-inpainting-0.1 has a 9-channel UNet trained
     specifically for clean mask seams. Worth pulling only if standard-model
     inpainting leaves edges you cannot feather away:

         cd ~/projects/myai/hyperreal
         uv run hf download diffusers/stable-diffusion-xl-1.0-inpainting-0.1

     Re-run ./bootstrap.sh --only optional-gpu after downloading to register
     it in the manifest.

GUIDE

    if has nvidia-smi; then
        manifest_add nvidia-smi nvidia-smi optional-gpu global windows-host-driver "nvidia-smi -L" optional "GPU passthrough from Windows host driver; CUDA toolkit/ML libs are project/container scoped"
        _optional_gpu_record_sdxl_inpaint
        log_ok "manifest updated — optional-gpu group"
    fi
}

_optional_gpu_record_sdxl_inpaint() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--diffusers--stable-diffusion-xl-1.0-inpainting-0.1"
    if [ -d "$hf_dir" ]; then
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
            "SDXL inpainting checkpoint (~7 GB, 9-ch UNet); clean mask seams vs standard inpainting. Download: cd ~/projects/myai/hyperreal && uv run hf download diffusers/stable-diffusion-xl-1.0-inpainting-0.1"
    fi
}
