#!/bin/bash
# Stage 40: shrink the rootfs by purging caches, locales, docs and fixing initramfs.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

mount_chroot() {
  for d in dev dev/pts proc sys run; do
    mountpoint -q "$ROOTFS_DIR/$d" || mount --rbind "/$d" "$ROOTFS_DIR/$d"
    mount --make-rslave "$ROOTFS_DIR/$d" 2>/dev/null || true
  done
}
umount_chroot() {
  for d in run sys proc dev/pts dev; do
    while mountpoint -q "$ROOTFS_DIR/$d"; do umount -lf "$ROOTFS_DIR/$d" 2>/dev/null || break; done
  done
}
trap umount_chroot EXIT INT TERM
mount_chroot

log "Regenerating initramfs (with live-boot for squashfs+overlay live boot)"
chroot "$ROOTFS_DIR" update-initramfs -u 2>&1 | tail -5

log "Cleaning apt cache, lists, doc, locales"
chroot "$ROOTFS_DIR" apt-get clean
chroot "$ROOTFS_DIR" apt-get autoremove -y --purge 2>&1 | tail -3 || true

# Purge most translations & extensive docs
rm -rf "$ROOTFS_DIR/var/cache/apt/"*
rm -rf "$ROOTFS_DIR/var/lib/apt/lists/"*
rm -rf "$ROOTFS_DIR/usr/share/doc"/*
rm -rf "$ROOTFS_DIR/usr/share/man"/*
rm -rf "$ROOTFS_DIR/usr/share/info"/*
# Keep en_US locale, drop the rest
find "$ROOTFS_DIR/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
  ! -name 'en' ! -name 'en_US' ! -name 'C' -exec rm -rf {} + 2>/dev/null || true
# Clear bash histories, machine-id (regenerated on first boot)
: > "$ROOTFS_DIR/etc/machine-id"
rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"
ln -sf /etc/machine-id "$ROOTFS_DIR/var/lib/dbus/machine-id"
rm -rf "$ROOTFS_DIR/root/.bash_history" "$ROOTFS_DIR/home/aurora/.bash_history"
rm -rf "$ROOTFS_DIR/tmp"/* "$ROOTFS_DIR/var/tmp"/* 2>/dev/null || true

log "Final rootfs size: $(du -sh "$ROOTFS_DIR" | cut -f1)"
touch "$ROOTFS_DIR/.cleaned"
