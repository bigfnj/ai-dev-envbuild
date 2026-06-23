#!/usr/bin/env bash
# image — image / media command-line tools (global). Python imaging libraries
# (Pillow, OpenCV, scikit-image) and ML models are PROJECT-LOCAL via uv,
# never global — see docs/architecture.md.
#
# Tools: imagemagick, ffmpeg, Pillow (ipython-injected), rembg (bg removal),
# realesrgan-ncnn-vulkan (AI upscaling + anime), pngquant/optipng (PNG opt),
# gifsicle (GIF), webp (WebP encode/decode), jpegoptim (JPEG opt), heif (HEIF/AVIF),
# huggingface-cli/hf (model download + repo management), yt-dlp + aria2 (media download).

image_desc() { echo "imagemagick, ffmpeg, Pillow, rembg (bg removal), realesrgan (AI upscale/anime), iopaint (AI inpainting), hf (HuggingFace CLI), yt-dlp + aria2, format tools (png/gif/webp/jpeg/heif)"; }

image_install() {
    apt_install imagemagick ffmpeg
    image_apt_extra
    image_pillow
    image_rembg
    image_realesrgan
    image_realesrgan_models
    image_iopaint
    image_hf
    image_ytdlp
    image_record_manifest
}

# Lossy/lossless PNG, GIF, WebP, JPEG optimization; HEIF/AVIF format support.
image_apt_extra() {
    apt_install \
        pngquant \
        optipng \
        gifsicle \
        webp \
        jpegoptim \
        libheif-examples \
        aria2 \
        potrace
}

# Pillow — inject into ipython's isolated pipx env for global REPL use.
# For project image code, use `uv add pillow` in the project venv instead.
image_pillow() {
    if ! has ipython; then
        log_warn "Pillow: ipython not installed — skipping inject (run python group first)"
        return 0
    fi
    if ipython -c "import PIL" >/dev/null 2>&1; then
        log_skip "Pillow already injected into ipython"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would pipx inject Pillow into ipython"; return 0; fi
    log_info "injecting Pillow into ipython pipx env"
    pipx inject ipython Pillow
}

# rembg — AI background removal using u2net models via ONNX Runtime (no GPU
# required; model downloads on first use ~170 MB). [cli] extra provides the
# click entry point. Custom idempotency check via `has rembg` because the [cli]
# suffix confuses pipx list --short package-name comparison.
image_rembg() {
    if has rembg; then
        log_skip "rembg already installed"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would pipx install rembg[cli]"; return 0; fi
    log_info "pipx install rembg[cli]"
    pipx install "rembg[cli]"
}

# Download the three ncnn model files for realesrgan-ncnn-vulkan. The binary zip
# (ncnn-vulkan v0.2.0) ships no models; the Real-ESRGAN Python project's v0.2.5.0
# ncnn zip is the authoritative pre-converted source. Idempotent: skips if the
# primary model is already present in the models/ directory.
image_realesrgan_models() {
    local destdir="$HOME/tools/realesrgan/realesrgan-ncnn-vulkan-${REALESRGAN_VERSION}-ubuntu"
    local modelsdir="$destdir/models"
    if [ -f "$modelsdir/realesrgan-x4plus.bin" ] && [ -f "$modelsdir/realesr-animevideov3-x2.bin" ]; then
        log_skip "realesrgan models already present ($modelsdir)"
        return 0
    fi
    if is_dry_run; then
        log_info "[DRY-RUN] would download realesrgan model files from Real-ESRGAN Python project v0.2.5.0 ncnn zip"
        return 0
    fi
    has realesrgan-ncnn-vulkan || { log_warn "realesrgan binary not installed — skipping model download"; return 0; }
    log_info "downloading realesrgan model files (Real-ESRGAN Python project v0.2.5.0 ncnn zip)"
    local zip; zip="$(mktemp --suffix=.zip)"
    if ! curl -fsSL "$REALESRGAN_MODELS_URL" -o "$zip"; then
        log_warn "realesrgan models download failed — skipping"; rm -f "$zip"; return 0
    fi
    verify_sha256 "$zip" "$REALESRGAN_MODELS_SHA256" || { rm -f "$zip"; return 1; }
    ensure_dir "$modelsdir"
    # Extract all five models: x4plus photo/anime + all three animevideov3 scale variants.
    unzip -q -o "$zip" \
        "models/realesrgan-x4plus.bin" \
        "models/realesrgan-x4plus.param" \
        "models/realesrgan-x4plus-anime.bin" \
        "models/realesrgan-x4plus-anime.param" \
        "models/realesr-animevideov3-x2.bin" \
        "models/realesr-animevideov3-x2.param" \
        "models/realesr-animevideov3-x3.bin" \
        "models/realesr-animevideov3-x3.param" \
        "models/realesr-animevideov3-x4.bin" \
        "models/realesr-animevideov3-x4.param" \
        -d "$destdir" 2>/dev/null || true
    rm -f "$zip"
    if [ -f "$modelsdir/realesrgan-x4plus.bin" ]; then
        log_ok "realesrgan models extracted to $modelsdir"
    else
        log_warn "realesrgan model extraction failed — models may be missing"
    fi
}

# iopaint — AI inpainting for object/person/background removal.
# LaMa (default) is a lightweight transformer; MAT and SD variants need more VRAM.
# Works on CPU (slow) or GPU (fast). PyTorch dependency makes the venv ~2-4 GB;
# models download on first use. Uses uv tool (not pipx): iopaint pins Pillow==9.5.0
# which fails to build on Python 3.13 — uv --overrides substitutes Pillow>=11.0.0.
# Pinned to Python 3.11: iopaint 1.6.0 imports `imghdr` which was removed in
# Python 3.13, causing an immediate crash on Python 3.14+ systems.
image_iopaint() {
    if has iopaint; then
        log_skip "iopaint already installed"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would uv tool install iopaint --python 3.11 (~2-4 GB including PyTorch)"; return 0; fi
    has uv || { log_err "uv not installed; cannot install iopaint (run python group first)"; return 1; }
    log_info "uv tool install iopaint --python 3.11 (PyTorch dependency -- large download)"
    local override; override="$(mktemp)"
    printf 'Pillow>=11.0.0\n' > "$override"
    uv tool install iopaint --python 3.11 --override "$override"
    rm -f "$override"
}

# Real-ESRGAN ncnn-Vulkan — AI upscaling, enhancement, and anime conversion.
# Five ncnn models ship in this group (extracted from the Real-ESRGAN Python
# project's v0.2.5.0 ncnn zip, the only official source for pre-converted files):
#   realesrgan-x4plus           (photos, 4x)
#   realesrgan-x4plus-anime     (anime/illustrations, 4x)
#   realesr-animevideov3-x2/3/4 (anime video frames, multi-scale)
# NOTE: realesrnet-x4plus (fast variant) exists only as a PyTorch .pth — it has
# never shipped in ncnn format from any official release and requires manual
# conversion with the ncnn toolchain to produce .bin/.param files.
# Invoke: realesrgan-ncnn-vulkan -i in.png -o out.png -n realesrgan-x4plus-anime
# GPU (Vulkan) or CPU mode; use -m /path to override model directory.
REALESRGAN_VERSION="v0.2.0"
REALESRGAN_SHA256="d0e8e1cf954f5cde11be4745dd912cc3774bef36f71c5b1cb8f74c4112b6e919"
# Model files come from the Python project's ncnn zip (binary-only ncnn-vulkan zip has none).
REALESRGAN_MODELS_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-ubuntu.zip"
REALESRGAN_MODELS_SHA256="e5aa6eb131234b87c0c51f82b89390f5e3e642b7b70f2b9bbe95b6a285a40c96"

image_realesrgan() {
    if has realesrgan-ncnn-vulkan; then
        log_skip "realesrgan-ncnn-vulkan already installed"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would download realesrgan-ncnn-vulkan $REALESRGAN_VERSION"; return 0; fi
    local url="https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan/releases/download/${REALESRGAN_VERSION}/realesrgan-ncnn-vulkan-${REALESRGAN_VERSION}-ubuntu.zip"
    local zip; zip="$(mktemp --suffix=.zip)"
    log_info "downloading realesrgan-ncnn-vulkan $REALESRGAN_VERSION"
    if ! curl -fsSL "$url" -o "$zip"; then
        log_warn "realesrgan-ncnn-vulkan download failed — skipping"; rm -f "$zip"; return 0
    fi
    verify_sha256 "$zip" "$REALESRGAN_SHA256" || { rm -f "$zip"; return 1; }
    local destdir="$HOME/tools/realesrgan"
    ensure_dir "$destdir"
    unzip -q -o "$zip" -d "$destdir"
    rm -f "$zip"
    local bin
    bin="$(find "$destdir" -maxdepth 2 -name "realesrgan-ncnn-vulkan" -type f | head -1)"
    if [ -n "$bin" ]; then
        chmod +x "$bin"
        ln -sf "$bin" "$HOME/tools/bin/realesrgan-ncnn-vulkan"
        log_ok "realesrgan-ncnn-vulkan $REALESRGAN_VERSION -> ~/tools/bin/"
    else
        log_warn "realesrgan-ncnn-vulkan: binary not found in expected archive layout"
    fi
}

# huggingface-cli (hf) — model download, upload, and repo management.
# Pure-Python HTTP client; no CUDA/torch dependency. Works machine-wide without
# a project venv, which is why it's global rather than project-local like the
# ML stacks it supports. Also installs the `tiny-agents` entry point.
image_hf() {
    if has hf; then
        log_skip "hf (huggingface-cli) already installed"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would pipx install huggingface_hub[cli]"; return 0; fi
    log_info "pipx install huggingface_hub[cli]"
    pipx install "huggingface_hub[cli]"
}

# yt-dlp — media downloader for URLs. ffmpeg from this group handles muxing,
# audio extraction, and format conversion when requested by yt-dlp.
image_ytdlp() {
    pipx_install yt-dlp
}

# SD1.5 inpainting model for iopaint. Recorded only when already downloaded;
# pre-download with: iopaint download --model runwayml/stable-diffusion-inpainting
# Fits comfortably on 8 GB VRAM (~2.6 GB weights). Requires iopaint --model sd1.5.
_image_record_sd15_inpaint() {
    local hf_dir="$HOME/.cache/huggingface/hub/models--runwayml--stable-diffusion-inpainting"
    if [ -d "$hf_dir" ]; then
        if is_dry_run; then log_info "[DRY-RUN] would record sd1.5-inpaint model"; return 0; fi
        local shim="$HOME/tools/bin/sd15-inpaint"
        cat > "$shim" <<SHIM
#!/usr/bin/env bash
test -d "$hf_dir"
SHIM
        chmod +x "$shim"
        manifest_add sd15-inpaint-checkpoint sd15-inpaint image container huggingface \
            "sd15-inpaint" optional \
            "SD1.5 inpainting model for iopaint (~2.6 GB; fits 8 GB VRAM). Use: iopaint start --model=sd1.5 --device=cuda --port=8080. Download: iopaint download --model runwayml/stable-diffusion-inpainting"
    fi
}

image_record_manifest() {
    local im=""
    if has magick; then im=magick; elif has convert; then im=convert; fi
    if [ -n "$im" ]; then
        # Detect is intentionally cross-platform: ImageMagick is `magick` on IM7
        # (Debian trixie) and `convert` on IM6 (Ubuntu 24.04). Recording a
        # tolerant detect lets `devtools check` pass regardless of which major
        # the host ships, even when the committed manifest was generated on the
        # other distro.
        manifest_add imagemagick "$im" image global apt "magick --version || convert --version" core "image manipulation/conversion/compositing (magick on IM7, convert on IM6)"
    fi
    if has ffmpeg; then
        manifest_add ffmpeg ffmpeg image global apt "ffmpeg -version" core "audio/video/image transcoding and conversion"
    fi
    if ipython -c "import PIL" >/dev/null 2>&1; then
        manifest_add pillow ipython image global pipx-inject \
            "ipython -c 'import PIL; print(PIL.__version__)'" core \
            "Python imaging library; injected into ipython — use 'uv add pillow' for project code" "ipython"
    fi
    if has pngquant;     then manifest_add pngquant     pngquant     image global apt "pngquant --version"    core "lossy PNG compression (up to 70% size reduction)"; fi
    if has optipng;      then manifest_add optipng      optipng      image global apt "optipng --version"     core "lossless PNG optimization"; fi
    if has gifsicle;     then manifest_add gifsicle     gifsicle     image global apt "gifsicle --version"    core "GIF creation, optimization, and frame editing"; fi
    if has cwebp;        then manifest_add webp         cwebp        image global apt "cwebp -version"        core "WebP encode/decode (cwebp, dwebp, webpinfo)"; fi
    if has jpegoptim;    then manifest_add jpegoptim    jpegoptim    image global apt "jpegoptim --version"   core "JPEG compression and metadata stripping"; fi
    if has heif-convert; then manifest_add libheif      heif-convert image global apt "command -v heif-convert" core "HEIF/AVIF read+write (heif-convert, heif-info)"; fi
    if has aria2c;       then manifest_add aria2        aria2c       image global apt "aria2c --version"       core "resumable/parallel downloader; useful as yt-dlp external downloader"; fi
    if has rembg; then
        manifest_add rembg rembg image global pipx "command -v rembg" core \
            "AI background removal (u2net, ONNX; no GPU required; model ~170 MB downloads on first use)"
    fi
    if has iopaint; then
        manifest_add iopaint iopaint image global uv-tool \
            "command -v iopaint" core \
            "AI inpainting: object/person/background removal (LaMa, MAT, SD models; CPU capable, GPU recommended for speed). Pinned to Python 3.11: imghdr removed in 3.13."
    fi
    _image_record_sd15_inpaint
    if has realesrgan-ncnn-vulkan; then
        manifest_add realesrgan-ncnn-vulkan realesrgan-ncnn-vulkan image global github-zip \
            "command -v realesrgan-ncnn-vulkan" core \
            "AI upscaling + anime conversion: models x4plus (photos), x4plus-anime, animevideov3, x4plus-fast; GPU (Vulkan) or CPU" \
            "" "xinntao/Real-ESRGAN-ncnn-vulkan"
    fi
    if has hf; then
        manifest_add huggingface-cli hf image global pipx \
            "hf --help" core \
            "HuggingFace model/dataset/repo management (hf download, hf upload, hf whoami, hf models ls); also installs tiny-agents"
    fi
    if has yt-dlp; then
        manifest_add yt-dlp yt-dlp image global pipx \
            "yt-dlp --version" core \
            "media downloader for URLs; pairs with ffmpeg for muxing, audio extraction, and format conversion"
    fi
    if has potrace; then
        manifest_add potrace potrace image global apt "potrace --version" core \
            "bitmap-to-vector conversion: transforms B&W PBM/BMP into smooth SVG/EPS/PDF paths (companion: mkbitmap)"
    fi
    log_ok "manifest updated — image group"
}
