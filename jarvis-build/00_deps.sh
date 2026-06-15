#!/bin/bash
# jarvis-build/00_deps.sh — install host tools needed to build the ISO.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Installing host build dependencies"
[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    debootstrap squashfs-tools xorriso isolinux syslinux-common \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools \
    ca-certificates wget curl rsync

log "Host dependencies ready"
