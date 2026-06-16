#!/usr/bin/env bash
# python — the Python layer.
#
# Ownership boundaries (see docs/architecture.md §2, §4):
#   - System Python stays Debian-managed. Never `pip install` into it.
#   - pipx owns GLOBAL Python CLIs (each in its own isolated venv).
#   - uv owns PROJECT dependency management AND Python version downloads.
#
# Deliberately NO pyenv: uv installs Python versions itself
# (`uv python install <ver>`) from prebuilt standalone builds — no compilation,
# no build deps. Running pyenv alongside uv would duplicate version management,
# the exact anti-pattern the spec warns against.
#
# pytest / mypy / and all libraries are PROJECT-LOCAL (uv add --dev) — a global
# pytest can't import a project's dependencies or plugins, so it has no place
# here.

python_desc() { echo "pipx, uv (+Python versions), ruff, ipython, jupyterlab, pandas+numpy (ipython-injected)"; }

python_install() {
    # System Python support: venv creation and C-extension builds in project envs.
    apt_install python3 python3-venv python3-dev pipx

    # uv: project deps + Python version manager. Installed via pipx so every
    # global Python CLI shares one install path (upgrade with `pipx upgrade uv`).
    pipx_install uv

    # Genuinely global CLIs — used across projects, don't import project code.
    pipx_install ruff        # linter + formatter (replaces black + flake8)
    pipx_install ipython     # scratch REPL
    pipx_install jupyterlab  # global launch point; kernels stay project-local

    python_inject_data
    python_record_manifest
}

# pandas + numpy — inject into ipython for ad-hoc data work in the global REPL.
# For project data code use `uv add pandas numpy` in the project venv instead.
python_inject_data() {
    if ! has ipython; then
        log_warn "data libs: ipython not installed — skipping inject (run python group first)"
        return 0
    fi
    local pkg import
    for entry in "pandas:pandas" "numpy:numpy"; do
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

python_record_manifest() {
    manifest_add python3    python3 python global apt  "python3 --version" core "system Python (Debian-managed; never pip-install into it)"
    manifest_add pipx       pipx    python global apt  "pipx --version"    core "manages global Python CLIs in isolated venvs"
    manifest_add uv         uv      python global pipx "uv --version"      core "project deps + Python versions (uv python install)"
    manifest_add ruff       ruff    python global pipx "ruff --version"    core "linter + formatter; replaces black/flake8"
    manifest_add ipython    ipython python global pipx "ipython --version" core "interactive REPL"
    manifest_add jupyterlab jupyter-lab python global pipx "jupyter-lab --version" core "launch with 'jupyter-lab'; project kernels stay local"
    if ipython -c "import pandas" >/dev/null 2>&1; then
        manifest_add pandas ipython python global pipx-inject \
            "ipython -c 'import pandas; print(pandas.__version__)'" core \
            "data manipulation and analysis; injected into ipython — use 'uv add pandas' for project code" "ipython"
    fi
    if ipython -c "import numpy" >/dev/null 2>&1; then
        manifest_add numpy ipython python global pipx-inject \
            "ipython -c 'import numpy; print(numpy.__version__)'" core \
            "numerical computing; injected into ipython — use 'uv add numpy' for project code" "ipython"
    fi
    log_ok "manifest updated — python group"
}
