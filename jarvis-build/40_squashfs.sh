#!/bin/bash
# jarvis-build/40_squashfs.sh — squash the chroot and lay out the live image.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Building squashfs + live image layout"
[ "$(id -u)" -eq 0 ] || die "run as root"

rm -rf "${IMAGE_DIR}"
mkdir -p "${IMAGE_DIR}/live" "${IMAGE_DIR}/isolinux" "${IMAGE_DIR}/boot/grub" \
         "${IMAGE_DIR}/EFI/boot"

# Copy kernel + initrd out of the chroot.
KVER=$(basename "$(ls -1 "${CHROOT_DIR}"/boot/vmlinuz-* | sort -V | tail -1)")
KVER="${KVER#vmlinuz-}"
cp "${CHROOT_DIR}/boot/vmlinuz-${KVER}" "${IMAGE_DIR}/live/vmlinuz"
cp "${CHROOT_DIR}/boot/initrd.img-${KVER}" "${IMAGE_DIR}/live/initrd.img"

# Squash the root filesystem (xz for size).
log "Compressing root filesystem (this can take a while)…"
mksquashfs "${CHROOT_DIR}" "${IMAGE_DIR}/live/filesystem.squashfs" \
    -comp xz -noappend -e boot \
    -e proc -e sys -e dev/pts -e run -e tmp

echo "${JARVIS_VOLID}" > "${IMAGE_DIR}/.disk/info" 2>/dev/null || \
    { mkdir -p "${IMAGE_DIR}/.disk"; echo "${JARVIS_VOLID}" > "${IMAGE_DIR}/.disk/info"; }

log "Squashfs ready: $(du -h "${IMAGE_DIR}/live/filesystem.squashfs" | cut -f1)"
