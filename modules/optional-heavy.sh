#!/usr/bin/env bash
# optional-heavy — large/niche tools that should NOT be installed by default.
# Opt in with: ./bootstrap.sh --with optional-heavy
#
# QEMU: full-system + userspace emulation, for running non-native OSes/arches
# (e.g. emulating an old system image, cross-arch binaries). Big install, so
# it's gated behind the flag. (DOSBox-X lives in the default `reverse` group.)

optional_heavy_desc() { echo "QEMU full-system + userspace emulation (opt-in)"; }

optional_heavy_install() {
    apt_install qemu-system qemu-utils qemu-user-static
    optional_heavy_record_manifest
}

optional_heavy_record_manifest() {
    if has qemu-system-x86_64; then manifest_add qemu-system qemu-system-x86_64 optional-heavy global apt "qemu-system-x86_64 --version" optional "full-system emulation (multiple arches)"; fi
    if has qemu-img;           then manifest_add qemu-utils  qemu-img           optional-heavy global apt "qemu-img --version"           optional "disk-image tooling (qemu-img, …)"; fi
    log_ok "manifest updated — optional-heavy group"
}
