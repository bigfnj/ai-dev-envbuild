#!/usr/bin/env bash
# office — document creation and automation tooling.
#
# System: LibreOffice (headless) for server-side DOCX/PPTX/XLSX → PDF conversion.
# Python: python-docx, python-pptx, openpyxl injected into the global ipython REPL
#   for ad-hoc document scripting without a project venv. Use `uv add` for project
#   code — the ipython injections are scratch-pad convenience only.
#
# LibreOffice is installed with --no-install-recommends to skip the full desktop
# stack (~300 MB vs ~1.5 GB). The headless mode covers the primary use case:
#   soffice --headless --convert-to pdf *.docx

office_desc() { echo "libreoffice (headless), python-docx, python-pptx, openpyxl (ipython-injected)"; }

office_install() {
    office_install_libreoffice
    office_inject_libs
    office_record_manifest
}

# Direct apt-get call so we can pass --no-install-recommends; apt_install() does
# not forward extra flags.
office_install_libreoffice() {
    if pkg_installed libreoffice; then
        log_skip "apt: libreoffice already installed"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would apt install --no-install-recommends libreoffice"; return 0; fi
    apt_refresh
    log_info "apt install --no-install-recommends libreoffice"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libreoffice
}

office_inject_libs() {
    if ! has ipython; then
        log_warn "office libs: ipython not installed — skipping inject (run python group first)"
        return 0
    fi
    local pkg import
    for entry in "python-docx:docx" "python-pptx:pptx" "openpyxl:openpyxl"; do
        pkg="${entry%%:*}"
        import="${entry##*:}"
        if ipython -c "import $import" >/dev/null 2>&1; then
            log_skip "$pkg already injected into ipython"
        else
            if is_dry_run; then log_info "[DRY-RUN] would pipx inject $pkg into ipython"; continue; fi
            log_info "injecting $pkg into ipython pipx env"
            pipx inject ipython "$pkg"
        fi
    done
}

office_record_manifest() {
    if has soffice; then
        manifest_add libreoffice soffice office global apt "soffice --version" core \
            "headless Office suite; converts DOCX/PPTX/XLSX to PDF via 'soffice --headless --convert-to pdf'"
    fi
    if ipython -c "import docx" >/dev/null 2>&1; then
        manifest_add python-docx ipython office global pipx-inject \
            "ipython -c 'import docx; print(docx.__version__)'" core \
            "DOCX read/write; injected into ipython — use 'uv add python-docx' for project code" "ipython"
    fi
    if ipython -c "import pptx" >/dev/null 2>&1; then
        manifest_add python-pptx ipython office global pipx-inject \
            "ipython -c 'import pptx; print(pptx.__version__)'" core \
            "PPTX read/write; injected into ipython — use 'uv add python-pptx' for project code" "ipython"
    fi
    if ipython -c "import openpyxl" >/dev/null 2>&1; then
        manifest_add openpyxl ipython office global pipx-inject \
            "ipython -c 'import openpyxl; print(openpyxl.__version__)'" core \
            "XLSX read/write; injected into ipython — use 'uv add openpyxl' for project code" "ipython"
    fi
    log_ok "manifest updated — office group"
}
