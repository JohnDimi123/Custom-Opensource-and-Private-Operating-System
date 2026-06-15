#!/bin/bash
# jarvis-installer/disk_install.sh — install live JARVIS OS to a disk.
# Usage: disk_install.sh /dev/sdX   (called by jarvis-pkg install-disk)
set -euo pipefail
TARGET="${1:?target disk required}"

echo "[*] Partitioning $TARGET (GPT, EFI + root)"
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart ESP fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on
parted -s "$TARGET" mkpart primary ext4 513MiB 100%

EFI="${TARGET}1"; ROOT="${TARGET}2"
[ -e "${TARGET}p1" ] && { EFI="${TARGET}p1"; ROOT="${TARGET}p2"; }  # nvme

echo "[*] Formatting"
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo "[*] Mounting"
mkdir -p /mnt/target
mount "$ROOT" /mnt/target
mkdir -p /mnt/target/boot/efi
mount "$EFI" /mnt/target/boot/efi

echo "[*] Copying live filesystem to disk"
unsquashfs -f -d /mnt/target /run/live/medium/live/filesystem.squashfs 2>/dev/null \
  || rsync -aAXH --exclude=/proc --exclude=/sys --exclude=/dev \
       --exclude=/run --exclude=/mnt / /mnt/target

echo "[*] Generating fstab"
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
EFI_UUID=$(blkid -s UUID -o value "$EFI")
cat > /mnt/target/etc/fstab <<EOF
UUID=$ROOT_UUID /         ext4 defaults 0 1
UUID=$EFI_UUID  /boot/efi vfat umask=0077 0 1
EOF

echo "[*] Installing bootloader"
for d in proc sys dev dev/pts run; do mount --bind /$d /mnt/target/$d; done
chroot /mnt/target /bin/bash -c "
  grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=JARVIS --recheck || grub-install $TARGET
  update-grub
  systemctl set-default graphical.target
"
echo "[*] Cleaning up"
for d in run dev/pts dev sys proc; do umount -l /mnt/target/$d || true; done
umount -R /mnt/target
echo "[✓] JARVIS OS installed to $TARGET. Remove the ISO and reboot."
