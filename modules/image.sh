#!/usr/bin/env bash
# image — image / media command-line tools (global). Python imaging libraries
# (Pillow, OpenCV, scikit-image) and ML models are PROJECT-LOCAL via uv,
# never global — see docs/architecture.md.
#
# Tools: imagemagick, ffmpeg, Pillow (ipython-injected), rembg (bg removal),
# realesrgan-ncnn-vulkan (AI upscaling + anime), pngquant/optipng (PNG opt),
# gifsicle (GIF), webp (WebP encode/decode), jpegoptim (JPEG opt), heif (HEIF/AVIF),
# huggingface-cli/hf (model download + repo management).

image_desc() { echo "imagemagick, ffmpeg, Pillow, rembg (bg removal), realesrgan (AI upscale/anime), hf (HuggingFace CLI), format tools (png/gif/webp/jpeg/heif)"; }

image_install() {
    apt_install imagemagick ffmpeg
    image_apt_extra
    image_pillow
    image_rembg
    image_realesrgan
    image_hf
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
        libheif-examples
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

# Real-ESRGAN ncnn-Vulkan — AI upscaling, enhancement, and anime conversion.
# Four models: realesrgan-x4plus (photos), realesrgan-x4plus-anime, realesr-animevideov3,
# realesrnet-x4plus (fast). GPU (Vulkan) or CPU mode.
# NOTE: v0.2.0 release ships the binary only — model files are downloaded separately.
#   mkdir -p ~/tools/realesrgan/realesrgan-ncnn-vulkan-v0.2.0-ubuntu/models
#   # Then obtain .param + .bin files from the project or community mirrors and
#   # place them there, or use -m /path/to/models to specify a custom path.
#   Invoke: realesrgan-ncnn-vulkan -i in.png -o out.png -n realesrgan-x4plus-anime
REALESRGAN_VERSION="v0.2.0"
REALESRGAN_SHA256="d0e8e1cf954f5cde11be4745dd912cc3774bef36f71c5b1cb8f74c4112b6e919"

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

image_record_manifest() {
    local im=""
    if has magick; then im=magick; elif has convert; then im=convert; fi
    if [ -n "$im" ]; then
        manifest_add imagemagick "$im" image global apt "$im --version" core "image manipulation/conversion/compositing"
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
    if has rembg; then
        manifest_add rembg rembg image global pipx "command -v rembg" core \
            "AI background removal (u2net, ONNX; no GPU required; model ~170 MB downloads on first use)"
    fi
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
    log_ok "manifest updated — image group"
}
