#!/bin/bash
# Stage 50: build the SquashFS image of the rootfs and stage ISO contents.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -d "$ROOTFS_DIR" ] || die "rootfs missing"

rm -rf "$ISO_STAGE_DIR"
mkdir -p "$ISO_STAGE_DIR/live" "$ISO_STAGE_DIR/boot/grub" "$ISO_STAGE_DIR/EFI/BOOT" "$ISO_STAGE_DIR/.disk"

# --- Locate kernel + initrd --------------------------------------------------
KERNEL=$(ls -1 "$ROOTFS_DIR"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
INITRD=$(ls -1 "$ROOTFS_DIR"/boot/initrd.img-* 2>/dev/null | sort -V | tail -1)
[ -n "$KERNEL" ] && [ -n "$INITRD" ] || die "kernel/initrd not found in $ROOTFS_DIR/boot"
log "Kernel: $KERNEL"
log "Initrd: $INITRD"

cp "$KERNEL" "$ISO_STAGE_DIR/live/vmlinuz"
cp "$INITRD" "$ISO_STAGE_DIR/live/initrd.img"

# --- Pack rootfs into SquashFS ----------------------------------------------
# -comp xz -Xbcj x86: best ratio for x86 binaries; ~30-40% smaller than gzip.
# -e exclude self/build artifacts. live-boot looks for /live/filesystem.squashfs by default.
log "Building SquashFS (this is the slow part) ..."
mksquashfs "$ROOTFS_DIR" "$ISO_STAGE_DIR/live/filesystem.squashfs" \
  -comp xz -Xbcj x86 \
  -b 1M \
  -noappend \
  -e boot/grub \
  -e var/cache/apt/archives \
  -wildcards \
  -e ".bootstrapped" -e ".packages-installed" -e ".customized" -e ".cleaned" \
  2>&1 | tail -5

# --- Manifest used by Calamares ---------------------------------------------
chroot_safe_dpkg() {
  # Run dpkg-query without needing chroot mounts
  dpkg-query --admindir="$ROOTFS_DIR/var/lib/dpkg" -W \
    -f='${Package} ${Version}\n' 2>/dev/null
}
chroot_safe_dpkg > "$ISO_STAGE_DIR/live/filesystem.packages"

cat > "$ISO_STAGE_DIR/.disk/info" <<EOF
${AURORA_NAME} ${AURORA_VERSION} "${AURORA_CODENAME}" - amd64 ($(date -u +%Y-%m-%d))
EOF
echo "full_cd/single" > "$ISO_STAGE_DIR/.disk/cd_type"

log "Stage size: $(du -sh "$ISO_STAGE_DIR" | cut -f1)"
log "Squashfs:   $(du -h "$ISO_STAGE_DIR/live/filesystem.squashfs" | cut -f1)"
