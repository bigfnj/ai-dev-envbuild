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

python_desc() { echo "pipx, uv (+Python versions), ruff, ipython, jupyterlab"; }

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

    python_record_manifest
}

python_record_manifest() {
    manifest_add python3    python3 python global apt  "python3 --version" core "system Python (Debian-managed; never pip-install into it)"
    manifest_add pipx       pipx    python global apt  "pipx --version"    core "manages global Python CLIs in isolated venvs"
    manifest_add uv         uv      python global pipx "uv --version"      core "project deps + Python versions (uv python install)"
    manifest_add ruff       ruff    python global pipx "ruff --version"    core "linter + formatter; replaces black/flake8"
    manifest_add ipython    ipython python global pipx "ipython --version" core "interactive REPL"
    manifest_add jupyterlab jupyter-lab python global pipx "jupyter-lab --version" core "launch with 'jupyter-lab'; project kernels stay local"
    log_ok "manifest updated — python group"
}
