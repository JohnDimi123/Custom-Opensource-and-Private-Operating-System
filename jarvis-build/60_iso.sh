#!/bin/bash
# jarvis-build/60_iso.sh — assemble the final hybrid BIOS+UEFI ISO.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Generating ISO image"
[ "$(id -u)" -eq 0 ] || die "run as root"

mkdir -p "${OUTPUT_DIR}"
ISO_OUT="${OUTPUT_DIR}/${JARVIS_ISO_NAME}"

ISOHDPFX=""
for c in /usr/lib/ISOLINUX/isohdpfx.bin /usr/lib/syslinux/isohdpfx.bin \
         /usr/lib/syslinux/mbr/isohdpfx.bin; do
    [ -f "$c" ] && ISOHDPFX="$c" && break
done
[ -n "${ISOHDPFX}" ] || die "isohdpfx.bin not found (install isolinux/syslinux-common)"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "${JARVIS_VOLID}" \
    -isohybrid-mbr "${ISOHDPFX}" \
    -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-catalog isolinux/boot.cat \
    -eltorito-alt-boot \
        -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat \
    -output "${ISO_OUT}" \
    "${IMAGE_DIR}"

log "ISO created: ${ISO_OUT}"
log "Size: $(du -h "${ISO_OUT}" | cut -f1)"
log "SHA256: $(sha256sum "${ISO_OUT}" | cut -d' ' -f1)"
echo
echo "  Boot it in VirtualBox / VMware / Hyper-V / Proxmox or write to USB:"
echo "    sudo dd if=${ISO_OUT} of=/dev/sdX bs=4M status=progress oflag=sync"
