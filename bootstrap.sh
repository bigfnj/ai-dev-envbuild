#!/usr/bin/env bash
# WSL2 Debian dev-environment bootstrap — idempotent, modular, agent-discoverable.
# Reproduces the full workstation on a fresh machine. See docs/architecture.md.
#
#   ./bootstrap.sh                 run all default groups
#   ./bootstrap.sh --only core     run only the named groups (comma-separated)
#   ./bootstrap.sh --with optional-gpu   defaults plus a flagged group
#   ./bootstrap.sh --skip image    defaults minus the named groups
#   ./bootstrap.sh --list          list groups and what each installs
#   ./bootstrap.sh --help
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"

DEFAULT_GROUPS=(core python node languages reverse data docs image containers)
OPTIONAL_GROUPS=(optional-heavy optional-gpu)
ALL_GROUPS=("${DEFAULT_GROUPS[@]}" "${OPTIONAL_GROUPS[@]}")

usage() {
    cat <<EOF
Usage: ./bootstrap.sh [options]

  (no options)     run all default groups:
                   ${DEFAULT_GROUPS[*]}
  --only  G1,G2    run only these groups
  --with  G1,G2    run default groups plus these (e.g. optional-gpu)
  --skip  G1,G2    run default groups except these
  --list           list groups and what each installs, then exit
  --help, -h       show this help

All groups: ${ALL_GROUPS[*]}
EOF
}

module_file() { echo "$REPO_ROOT/modules/$1.sh"; }
fn_name()     { echo "${1//-/_}"; }   # optional-gpu -> optional_gpu

list_groups() {
    local g f fn
    for g in "${ALL_GROUPS[@]}"; do
        f="$(module_file "$g")"
        if [ -f "$f" ]; then
            # shellcheck disable=SC1090
            . "$f"
            fn="$(fn_name "$g")_desc"
            if type -t "$fn" >/dev/null; then
                printf '  %-16s %s\n' "$g" "$("$fn")"
            else
                printf '  %-16s %s\n' "$g" "(no description)"
            fi
        else
            printf '  %-16s %s\n' "$g" "(not implemented yet)"
        fi
    done
}

run_group() {
    local g="$1" f fn
    f="$(module_file "$g")"
    if [ ! -f "$f" ]; then
        log_warn "group '$g' not implemented yet (no $f) — skipping"
        return 0
    fi
    log_group "$g"
    # shellcheck disable=SC1090
    . "$f"
    fn="$(fn_name "$g")_install"
    if type -t "$fn" >/dev/null; then
        "$fn"
    else
        log_warn "module '$g' defines no $fn() — skipping"
    fi
}

main() {
    local groups=("${DEFAULT_GROUPS[@]}")
    while [ $# -gt 0 ]; do
        case "$1" in
            --only) IFS=, read -r -a groups <<< "${2:-}"; shift 2;;
            --with)
                local extra=(); IFS=, read -r -a extra <<< "${2:-}"
                groups=("${DEFAULT_GROUPS[@]}" "${extra[@]}"); shift 2;;
            --skip)
                local skip=(); IFS=, read -r -a skip <<< "${2:-}"
                local filtered=() g s drop
                for g in "${DEFAULT_GROUPS[@]}"; do
                    drop=0; for s in "${skip[@]}"; do [ "$g" = "$s" ] && drop=1; done
                    [ "$drop" -eq 0 ] && filtered+=("$g")
                done
                groups=("${filtered[@]}"); shift 2;;
            --list) list_groups; exit 0;;
            --help|-h) usage; exit 0;;
            *) log_err "unknown option: $1"; usage; exit 1;;
        esac
    done

    # Make tools installed earlier in this run (pipx apps, ~/tools/bin links)
    # usable by later modules in the same process, before shellrc is sourced.
    export PATH="$HOME/.local/bin:$HOME/tools/bin:$PATH"

    ensure_dir "$LOG_DIR"
    local logfile
    logfile="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
    log_info "logging to $logfile"
    exec > >(tee -a "$logfile") 2>&1

    log_info "groups: ${groups[*]}"
    local g
    for g in "${groups[@]}"; do run_group "$g"; done

    log_group "done"
    log_ok "bootstrap complete — run 'devtools report' for the inventory"
}

main "$@"
