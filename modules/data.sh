#!/usr/bin/env bash
# data — lightweight local data tooling (CLI). Heavy DS/ML libraries (pandas,
# numpy, scikit-learn, pytorch, …) are PROJECT-LOCAL via uv, never global.
# sqlite3 itself lives in the core group.

data_desc() { echo "duckdb CLI, sqlite-utils, csvkit, rclone"; }

data_install() {
    data_duckdb
    apt_install rclone         # cloud/local sync and artifact movement
    pipx_install sqlite-utils   # SQLite automation/CLI
    pipx_install csvkit         # csvlook, csvcut, csvstat, in2csv, …
    data_record_manifest
}

# DuckDB CLI — standalone glibc binary from GitHub releases into ~/tools/bin.
# (The pip `duckdb` package is the Python library, not the CLI — different thing.)
# Pinned to a known-good release; bump DUCKDB_VERSION + SHA256 together after
# testing, then update manifest_add source_repo for devtools outdated checks.
DUCKDB_VERSION="v1.5.3"
DUCKDB_SHA256=""  # set to sha256sum of duckdb_cli-linux-amd64.zip after verifying

data_duckdb() {
    if has duckdb; then
        log_skip "duckdb already installed ($(duckdb --version 2>/dev/null))"
        return 0
    fi
    if is_dry_run; then log_info "[DRY-RUN] would download DuckDB CLI $DUCKDB_VERSION"; return 0; fi
    local url="https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip"
    local zip; zip="$(mktemp --suffix=.zip)"
    log_info "downloading DuckDB CLI $DUCKDB_VERSION"
    if curl -fsSL "$url" -o "$zip"; then
        verify_sha256 "$zip" "$DUCKDB_SHA256" || { rm -f "$zip"; return 1; }
        unzip -q -o "$zip" -d "$HOME/tools/bin"
        chmod +x "$HOME/tools/bin/duckdb"
        log_ok "duckdb -> ~/tools/bin/duckdb"
    else
        log_warn "duckdb download failed — skipping"
    fi
    rm -f "$zip"
}

data_record_manifest() {
    if has duckdb;       then manifest_add duckdb       duckdb       data global github-zip "duckdb --version"       core "in-process analytical SQL over CSV/Parquet/JSON" "" "duckdb/duckdb"; fi
    if has rclone;       then manifest_add rclone       rclone       data global apt        "rclone version"          core "cloud/local sync and artifact movement"; fi
    if has sqlite-utils; then manifest_add sqlite-utils sqlite-utils data global pipx       "sqlite-utils --version" core "SQLite CLI + automation"; fi
    if has csvlook;      then manifest_add csvkit       csvlook      data global pipx       "csvlook --version"      core "CSV inspection/conversion (csvlook, csvcut, …)"; fi
    log_ok "manifest updated — data group"
}
