#!/bin/bash
# Stage 10: bootstrap a minimal Debian rootfs. ~250 MB after this stage.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

if [ -f "$ROOTFS_DIR/.bootstrapped" ]; then
  log "Bootstrap already complete; skipping. (rm $ROOTFS_DIR/.bootstrapped to redo)"
  exit 0
fi

log "Bootstrapping Debian $DEBIAN_RELEASE into $ROOTFS_DIR"
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

# --variant=minbase: smallest functional set; we add packages explicitly later.
# --include: ca-certificates so apt over https works in stage 20.
debootstrap \
  --arch=amd64 \
  --variant=minbase \
  --components="main" \
  --include="ca-certificates,gnupg,apt-transport-https,locales,tzdata" \
  "$DEBIAN_RELEASE" \
  "$ROOTFS_DIR" \
  "$DEBIAN_MIRROR" 2>&1 | tail -20

touch "$ROOTFS_DIR/.bootstrapped"
log "Bootstrap complete: $(du -sh "$ROOTFS_DIR" | cut -f1)"
