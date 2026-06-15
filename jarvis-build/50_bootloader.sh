#!/bin/bash
# jarvis-build/50_bootloader.sh — set up ISOLINUX (BIOS) + GRUB (UEFI).
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Configuring bootloaders (BIOS + UEFI)"
[ "$(id -u)" -eq 0 ] || die "run as root"

BOOT_PARAMS="boot=live components quiet splash"

# ---------- BIOS: ISOLINUX ----------
cp /usr/lib/ISOLINUX/isolinux.bin "${IMAGE_DIR}/isolinux/" 2>/dev/null || \
   cp /usr/lib/syslinux/isolinux.bin "${IMAGE_DIR}/isolinux/"
for mod in ldlinux.c32 libcom32.c32 libutil.c32 vesamenu.c32; do
    find /usr/lib/syslinux /usr/lib/ISOLINUX -name "$mod" -exec cp {} "${IMAGE_DIR}/isolinux/" \; 2>/dev/null || true
done

cat > "${IMAGE_DIR}/isolinux/isolinux.cfg" <<EOF
UI vesamenu.c32
PROMPT 0
TIMEOUT 50
MENU TITLE J.A.R.V.I.S OS
MENU BACKGROUND splash.png

LABEL jarvis
  MENU LABEL Boot JARVIS OS
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${BOOT_PARAMS}

LABEL recovery
  MENU LABEL JARVIS OS (recovery mode)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img boot=live components systemd.unit=jarvis-recovery.target

LABEL ramdisk
  MENU LABEL JARVIS OS (load to RAM)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${BOOT_PARAMS} toram
EOF

# ---------- UEFI: GRUB ----------
cat > "${IMAGE_DIR}/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0
insmod all_video
menuentry "Boot JARVIS OS" {
    linux /live/vmlinuz ${BOOT_PARAMS}
    initrd /live/initrd.img
}
menuentry "JARVIS OS (recovery mode)" {
    linux /live/vmlinuz boot=live components systemd.unit=jarvis-recovery.target
    initrd /live/initrd.img
}
menuentry "JARVIS OS (load to RAM)" {
    linux /live/vmlinuz ${BOOT_PARAMS} toram
    initrd /live/initrd.img
}
EOF

# Build a standalone GRUB EFI binary embedding the config search.
cat > "${BUILD_DIR}/grub-embed.cfg" <<EOF
search --no-floppy --set=root --file /live/vmlinuz
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output="${IMAGE_DIR}/EFI/boot/bootx64.efi" \
    --modules="part_gpt part_msdos fat iso9660 all_video" \
    "boot/grub/grub.cfg=${BUILD_DIR}/grub-embed.cfg"

# Create the El-Torito EFI boot image (FAT) that xorriso references.
EFI_IMG="${IMAGE_DIR}/boot/grub/efi.img"
dd if=/dev/zero of="${EFI_IMG}" bs=1M count=10
mkfs.vfat "${EFI_IMG}"
mmd  -i "${EFI_IMG}" ::/EFI ::/EFI/boot
mcopy -i "${EFI_IMG}" "${IMAGE_DIR}/EFI/boot/bootx64.efi" ::/EFI/boot/bootx64.efi

log "Bootloaders ready (BIOS isolinux + UEFI grub)"
