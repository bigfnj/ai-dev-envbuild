#!/usr/bin/env bash
# languages — compiled / managed language toolchains beyond Python and Node.
#
# PATH discipline: Debian trixie ships CURRENT Go (1.24), OpenJDK (21), and
# Maven, so those go through apt and land in /usr/bin — no PATH additions.
# Rust is the one true version manager here (rustup self-manages ~/.cargo/bin
# via its own shell-rc line, which the architecture explicitly allows). .NET is
# not in apt; it's best-effort via Microsoft's feed and never fails the group.
#
# Build tools (Gradle/Maven) are mostly project-local (./gradlew, wrapper) —
# apt Gradle is ancient (4.x) so it's skipped; Maven is current and useful for
# quick project bootstrapping, so it's included.

languages_desc() { echo "Rust (rustup), Go, OpenJDK + Maven, .NET (best-effort)"; }

languages_install() {
    languages_rust
    languages_go
    languages_java
    languages_dotnet
    languages_record_manifest
}

# Rust via rustup — default profile includes cargo, rustfmt, clippy. rustup adds
# its own `. ~/.cargo/env` line to the shell rc (its managed PATH entry).
languages_rust() {
    if has cargo; then
        log_skip "rust already installed ($(cargo --version))"
        return 0
    fi
    log_info "installing rustup (profile: cargo, rustfmt, clippy)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Make cargo usable for the rest of this bootstrap run.
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
}

# Go from apt — trixie ships 1.24, current enough; lands on /usr/bin.
languages_go() { apt_install golang-go; }

# OpenJDK + Maven from apt — both current on trixie, both on /usr/bin.
# Gradle intentionally omitted (apt's is 4.x; projects use the ./gradlew wrapper).
languages_java() { apt_install default-jdk maven; }

# .NET — not in Debian apt. Best-effort via Microsoft's package feed for this
# Debian release; if the feed has no build for this version, warn and move on.
languages_dotnet() {
    if has dotnet; then
        log_skip "dotnet already installed ($(dotnet --version))"
        return 0
    fi
    local ver; ver="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    local url="https://packages.microsoft.com/config/debian/${ver}/packages-microsoft-prod.deb"
    local tmp; tmp="$(mktemp --suffix=.deb)"
    if [ -n "$ver" ] && curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
        log_info ".NET: adding Microsoft package feed for Debian ${ver}"
        if sudo dpkg -i "$tmp" >/dev/null 2>&1; then
            sudo apt-get update -qq
            if ! { apt_install dotnet-sdk-9.0 || apt_install dotnet-sdk-8.0; }; then
                log_warn ".NET: no SDK package in the feed — skipping"
            fi
        else
            log_warn ".NET: could not register Microsoft feed — skipping"
        fi
    else
        log_warn ".NET: no Microsoft apt feed for Debian ${ver:-unknown} — skipping (manual: curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS)"
    fi
    rm -f "$tmp"
}

languages_record_manifest() {
    if has cargo;       then manifest_add rust    cargo   languages global rustup "cargo --version"    core "rustup toolchain: cargo, rustc, rustfmt, clippy"; fi
    if has rustfmt;     then manifest_add rustfmt rustfmt languages global rustup "rustfmt --version"  core "Rust formatter (rustup component)"; fi
    if has cargo-clippy;then manifest_add clippy  cargo-clippy languages global rustup "cargo-clippy --version" core "Rust linter — run via 'cargo clippy'"; fi
    if has go;          then manifest_add go      go      languages global apt    "go version"         core "Go toolchain (incl. gofmt) — trixie apt"; fi
    if has java;        then manifest_add openjdk java    languages global apt    "java --version"     core "OpenJDK (default-jdk) — trixie apt"; fi
    if has mvn;         then manifest_add maven   mvn     languages global apt    "mvn --version"      core "build tool; Gradle uses ./gradlew per project"; fi
    if has dotnet;      then manifest_add dotnet  dotnet  languages global microsoft-apt "dotnet --version" core ".NET SDK via Microsoft feed"; fi
    log_ok "manifest updated — languages group"
}
