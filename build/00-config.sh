#!/bin/bash
# AuroraOS build configuration. Sourced by every build stage.

# -- Identity ------------------------------------------------------------------
export AURORA_NAME="AuroraOS"
export AURORA_VERSION="1.0"
export AURORA_CODENAME="Lumen"
export AURORA_HOSTNAME="aurora"
export AURORA_LIVE_USER="aurora"

# -- Base distro ---------------------------------------------------------------
# Debian stable: tested kernel, in-tree Hyper-V drivers (hv_vmbus, hv_storvsc,
# hv_netvsc, hyperv_drm, hyperv_fb), systemd, broad package coverage.
export DEBIAN_RELEASE="bookworm"
export DEBIAN_MIRROR="http://deb.debian.org/debian"
export DEBIAN_COMPONENTS="main contrib non-free-firmware"

# -- Paths ---------------------------------------------------------------------
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
export ROOTFS_DIR="$WORK_DIR/rootfs"
export ISO_STAGE_DIR="$WORK_DIR/iso"
export OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
export ISO_OUTPUT="$OUT_DIR/${AURORA_NAME}-${AURORA_VERSION}-amd64.iso"

# Build tools (provided by the sandbox)
export QEMU_BIN="${QEMU_BIN:-/projects/sandbox/.buildtools/qemu-system-x86_64}"
export OVMF_CODE="${OVMF_CODE:-/projects/sandbox/.buildtools/ovmf-extract/usr/share/OVMF/OVMF_CODE_4M.fd}"
export OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/projects/sandbox/.buildtools/ovmf-extract/usr/share/OVMF/OVMF_VARS_4M.fd}"

# -- Logging -------------------------------------------------------------------
export AURORA_LOG="$WORK_DIR/build.log"
log()   { printf '\033[1;36m[aurora]\033[0m %s\n' "$*" | tee -a "$AURORA_LOG" >&2; }
warn()  { printf '\033[1;33m[aurora WARN]\033[0m %s\n' "$*" | tee -a "$AURORA_LOG" >&2; }
die()   { printf '\033[1;31m[aurora ERR ]\033[0m %s\n' "$*" | tee -a "$AURORA_LOG" >&2; exit 1; }

mkdir -p "$WORK_DIR" "$OUT_DIR"
