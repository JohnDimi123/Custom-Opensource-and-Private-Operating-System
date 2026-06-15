#!/bin/bash
# jarvis-build/config.sh — shared build configuration.
# Sourced by every build stage and by build_jarvis_iso.sh.

# --- distro base ---
export JARVIS_DISTRO="debian"
export JARVIS_SUITE="bookworm"            # Debian 12 LTS
export JARVIS_MIRROR="http://deb.debian.org/debian"
export JARVIS_ARCH="amd64"

# --- naming ---
export JARVIS_HOSTNAME="jarvis"
export JARVIS_USER="operator"
export JARVIS_PASS="jarvis"               # live default; change on disk install
export JARVIS_ISO_NAME="jarvis-os.iso"
export JARVIS_VOLID="JARVIS_OS"

# --- paths (relative to repo root) ---
export JARVIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BUILD_DIR="${JARVIS_ROOT}/build"
export CHROOT_DIR="${BUILD_DIR}/chroot"
export IMAGE_DIR="${BUILD_DIR}/image"
export OUTPUT_DIR="${JARVIS_ROOT}/dist"

# --- features ---
export JARVIS_FULL_VOICE="${JARVIS_FULL_VOICE:-0}"   # 1 = bake whisper/piper/oww
export JARVIS_KERNEL_PKG="linux-image-${JARVIS_ARCH}"

log()  { printf "\033[36m[jarvis-build]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[jarvis-build] WARN:\033[0m %s\n" "$*"; }
die()  { printf "\033[31m[jarvis-build] ERROR:\033[0m %s\n" "$*" >&2; exit 1; }
