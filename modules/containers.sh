#!/usr/bin/env bash
# containers — Docker Engine (inside WSL) + Compose + devcontainer CLI.
#
# If `docker` is already on PATH (e.g. Docker Desktop's WSL integration), the
# engine install is skipped — we don't fight an existing Docker. Otherwise we
# install Docker Engine from Docker's official apt repo, enable the daemon via
# systemd when present, and add the user to the `docker` group (effective on
# next login). devcontainer CLI comes from npm (user prefix).
#
# Podman is a drop-in alternative if Docker isn't desired (not installed here).
# Heavy/risky workloads (ML/CUDA, untrusted RE) belong in containers per
# docs/architecture.md §4.

containers_desc() { echo "Docker Engine + Compose (or existing Docker Desktop), devcontainer CLI"; }

containers_install() {
    containers_docker_engine
    containers_docker_service
    containers_docker_group
    npm_global @devcontainers/cli devcontainer
    containers_record_manifest
}

# Install Docker Engine from the official apt repo — unless docker already exists.
containers_docker_engine() {
    if has docker; then
        log_skip "docker already present ($(docker --version 2>/dev/null)) — not installing engine (Docker Desktop integration?)"
        return 0
    fi
    if is_dry_run; then
        log_info "[DRY-RUN] would add Docker apt repo and install Docker Engine + Compose"
        return 0
    fi
    local arch codename
    arch="$(dpkg --print-architecture)"
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    if [ -z "$codename" ] || ! curl -fsI "https://download.docker.com/linux/debian/dists/$codename/Release" >/dev/null 2>&1; then
        log_warn "Docker apt repo has no '$codename' dist — falling back to bookworm"
        codename=bookworm
    fi

    log_info "adding Docker apt repo (debian/$codename)"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $codename stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    # Force a refresh so the freshly-added repo is seen even if apt was already
    # updated earlier in this run.
    _APT_UPDATED=0
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Enable + start the daemon when systemd is the init system; otherwise explain.
containers_docker_service() {
    has docker || return 0
    if is_dry_run; then log_info "[DRY-RUN] would enable/start docker service when systemd is present"; return 0; fi
    if [ -d /run/systemd/system ]; then
        if sudo systemctl enable --now docker >/dev/null 2>&1; then
            log_ok "docker service enabled + started (systemd)"
        else
            log_warn "could not enable docker service via systemd — start it manually"
        fi
    else
        log_warn "no systemd — start Docker manually with 'sudo dockerd &'; on WSL2 enable systemd via /etc/wsl.conf ([boot] systemd=true) and restart WSL; on native Linux check your init system"
    fi
}

# Add the user to the docker group so docker runs without sudo (next login).
containers_docker_group() {
    has docker || return 0
    if is_dry_run; then log_info "[DRY-RUN] would ensure docker group membership for $USER"; return 0; fi
    getent group docker >/dev/null || sudo groupadd docker
    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
        log_skip "$USER already in docker group"
    else
        sudo usermod -aG docker "$USER"
        log_warn "added $USER to 'docker' group — log out/in (or run 'newgrp docker') before using docker without sudo"
    fi
}

containers_record_manifest() {
    if has docker; then
        manifest_add docker         docker docker global docker-apt "docker --version"        core "Docker Engine (or existing Docker Desktop)"
        manifest_add docker-compose docker docker global docker-apt "docker compose version"  core "Compose v2 plugin — invoke as 'docker compose'"
    fi
    if has devcontainer; then
        manifest_add devcontainer devcontainer containers global npm-user "devcontainer --version" core "Dev Containers CLI"
    fi
    log_ok "manifest updated — containers group"
}
