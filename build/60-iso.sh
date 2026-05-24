#!/bin/bash
# Stage 60: assemble the bootable hybrid UEFI ISO.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ISO_STAGE_DIR/live/filesystem.squashfs" ] || die "squashfs not built"

# --- GRUB config that runs on the ISO ---------------------------------------
# Note: live-boot kernel cmdline:
#   boot=live   -> tells initramfs to mount squashfs as the rootfs
#   components  -> activates live-config (autologin via lightdm conf, etc.)
#   quiet splash plymouth.ignore-serial-consoles -> clean Plymouth boot
#   noprompt    -> don't pause before unmounting media on shutdown
cat > "$ISO_STAGE_DIR/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

# Serial console: lets the test pipeline (and headless servers) see boot output.
serial --unit=0 --speed=115200
terminal_input  --append serial
terminal_output --append serial

# Try graphical menu first; fall back gracefully if FB unavailable
if loadfont /boot/grub/fonts/unicode.pf2 ; then
  insmod all_video
  insmod gfxterm
  set gfxmode=auto
  terminal_output --append gfxterm
fi

set color_normal=white/black
set color_highlight=black/light-cyan
set menu_color_normal=white/black
set menu_color_highlight=black/light-cyan

# Hyper-V's UEFI firmware triggers GRUB's "linuxefi" codepath, which on some
# GRUB builds (Debian/Ubuntu 2.06) tries to dynamically load linuxefi.mod even
# when the menuentry uses "linux".  Insmodding it up-front (with || true so it's
# a no-op on builds that have unified linux+linuxefi) avoids the chained error
# "linuxefi.mod not found"  ->  "you need to load the kernel first".
insmod linux || true
insmod linuxefi || true

menuentry "AuroraOS  -  Live Session" {
    linux  /live/vmlinuz boot=live components quiet splash plymouth.ignore-serial-consoles console=tty0 console=ttyS0,115200n8 video=hyperv_fb:1920x1080 video=1920x1080
    initrd /live/initrd.img
}

menuentry "AuroraOS  -  Live Session  (safe graphics)" {
    linux  /live/vmlinuz boot=live components nomodeset vga=normal console=tty0 console=ttyS0,115200n8
    initrd /live/initrd.img
}

menuentry "Install AuroraOS to disk" {
    linux  /live/vmlinuz boot=live components quiet splash aurora.installer=true console=tty0 console=ttyS0,115200n8 video=hyperv_fb:1920x1080 video=1920x1080
    initrd /live/initrd.img
}

menuentry "AuroraOS  -  Verbose boot (debug)" {
    linux  /live/vmlinuz boot=live components debug console=tty0 console=ttyS0,115200n8 video=1920x1080
    initrd /live/initrd.img
}

menuentry "Reboot"   { reboot }
menuentry "Shutdown" { halt }
EOF

# --- Build standalone UEFI loader -------------------------------------------
# The grub-embed.cfg only finds the real grub.cfg on the iso9660 filesystem.
cat > "$WORK_DIR/grub-embed.cfg" <<'EOF'
# Robust standalone GRUB EFI bootstrap. We try several strategies because
# different UEFI firmwares (OVMF, Hyper-V, real hardware) expose the CD
# differently.
insmod part_gpt
insmod part_msdos
insmod iso9660
insmod fat
insmod search
insmod search_label
insmod search_fs_file
insmod search_fs_uuid
insmod normal
insmod configfile

# Try them in order. The first one that succeeds wins.
set _aurora_found=0

# 1. Volume label (xorriso writes 'AURORA_1_0').
search --no-floppy --label AURORA_1_0 --set=_root
if [ -n "$_root" ]; then set root=$_root; set _aurora_found=1; fi

# 2. Marker file path.
if [ "$_aurora_found" = "0" ]; then
  search --no-floppy --file /.disk/aurora_iso_marker --set=_root
  if [ -n "$_root" ]; then set root=$_root; set _aurora_found=1; fi
fi

# 3. /.disk/info (Debian-style)
if [ "$_aurora_found" = "0" ]; then
  search --no-floppy --file /.disk/info --set=_root
  if [ -n "$_root" ]; then set root=$_root; set _aurora_found=1; fi
fi

# 4. Iterate explicitly: cd0, hd0, hd1, hd2 ...
if [ "$_aurora_found" = "0" ]; then
  for dev in cd0 cd1 cd2 hd0 hd1 hd2 hd3 hd4 ; do
    if [ -e "($dev)/.disk/aurora_iso_marker" ]; then
      set root=$dev
      set _aurora_found=1
      break
    fi
  done
fi

# 5. Last resort: the directory the EFI binary itself loaded from.
if [ "$_aurora_found" = "0" ]; then
  set root=$cmdpath
fi

set prefix=($root)/boot/grub
configfile $prefix/grub.cfg
EOF

# Filter the desired GRUB modules to those actually present on the build host
# (linuxefi.mod doesn't exist on Fedora/AL because they unified linux+linuxefi).
GRUB_DIR=""
for cand in /usr/lib/grub/x86_64-efi /usr/lib/grub2/x86_64-efi /usr/share/grub2/x86_64-efi; do
  [ -d "$cand" ] && GRUB_DIR="$cand" && break
done
[ -n "$GRUB_DIR" ] || die "Cannot find GRUB x86_64-efi modules dir"

GRUB_MODULES_DESIRED="part_gpt part_msdos fat iso9660 normal configfile search search_label search_fs_uuid search_fs_file linux linuxefi echo all_video gfxterm gfxterm_background gfxmenu boot loadenv test true help serial terminal sleep halt reboot ls cat password password_pbkdf2 ext2 udf squash4 png jpeg gzio xzio lzopio video_bochs video_cirrus efi_gop efi_uga chain"
GRUB_MODULES=""
for m in $GRUB_MODULES_DESIRED; do
  [ -f "$GRUB_DIR/$m.mod" ] && GRUB_MODULES="$GRUB_MODULES $m"
done

log "Building x86_64-efi GRUB image (BOOTX64.EFI)"
grub2-mkstandalone \
  --format=x86_64-efi \
  --output="$ISO_STAGE_DIR/EFI/BOOT/BOOTX64.EFI" \
  --modules="$GRUB_MODULES" \
  --locales="" --themes="" \
  --fonts="unicode" \
  "boot/grub/grub.cfg=$WORK_DIR/grub-embed.cfg" 2>&1 | tail -3

# Stage GRUB unicode font for gfxterm
mkdir -p "$ISO_STAGE_DIR/boot/grub/fonts"
if [ -f /usr/share/grub/unicode.pf2 ]; then
  cp /usr/share/grub/unicode.pf2 "$ISO_STAGE_DIR/boot/grub/fonts/unicode.pf2"
fi

# --- Stage GRUB module directories on the ISO -------------------------------
# Some UEFI firmwares (notably Hyper-V) cause GRUB's linux command to
# dynamically load extra .mod files at runtime even when the modules are also
# embedded in the standalone EFI binary.  Make sure those .mod files are also
# present at the path GRUB looks for them: ($root)/boot/grub/<arch>/.
log "Staging GRUB module directories on the ISO"
for arch in x86_64-efi i386-pc; do
  src=""
  for cand in /usr/lib/grub/$arch /usr/share/grub2/$arch /usr/lib/grub2/$arch; do
    [ -d "$cand" ] && src="$cand" && break
  done
  if [ -n "$src" ]; then
    mkdir -p "$ISO_STAGE_DIR/boot/grub/$arch"
    cp -a "$src"/*.mod "$ISO_STAGE_DIR/boot/grub/$arch/" 2>/dev/null || true
    cp -a "$src"/*.lst "$ISO_STAGE_DIR/boot/grub/$arch/" 2>/dev/null || true
    cp -a "$src"/efiemu*.o "$ISO_STAGE_DIR/boot/grub/$arch/" 2>/dev/null || true
    log "  staged $arch from $src"
  else
    warn "  no module dir for $arch"
  fi
done

# --- Build BIOS (i386-pc) loader for legacy fallback ------------------------
log "Building i386-pc GRUB image (eltorito.img) for legacy BIOS fallback"
grub2-mkstandalone \
  --format=i386-pc \
  --output="$WORK_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --themes="" --fonts="" \
  "boot/grub/grub.cfg=$WORK_DIR/grub-embed.cfg" 2>&1 | tail -3 || warn "BIOS image build skipped"

if [ -f "$WORK_DIR/core.img" ] && [ -f /usr/lib/grub/i386-pc/cdboot.img ]; then
  cat /usr/lib/grub/i386-pc/cdboot.img "$WORK_DIR/core.img" > "$ISO_STAGE_DIR/boot/grub/eltorito.img"
fi

# --- Build the EFI System Partition image (FAT) -----------------------------
ESP_SIZE_KB=$(( $(du -sk "$ISO_STAGE_DIR/EFI/BOOT/BOOTX64.EFI" | cut -f1) + 2048 ))
ESP_SIZE_KB=$(( ((ESP_SIZE_KB + 1023) / 1024) * 1024 ))   # round up to MB
log "Creating EFI System Partition image (${ESP_SIZE_KB}K)"
dd if=/dev/zero of="$WORK_DIR/efi.img" bs=1K count=$ESP_SIZE_KB status=none
mkfs.vfat -n EFIESP "$WORK_DIR/efi.img" >/dev/null
mmd -i "$WORK_DIR/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$WORK_DIR/efi.img" "$ISO_STAGE_DIR/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
cp "$WORK_DIR/efi.img" "$ISO_STAGE_DIR/boot/grub/efi.img"

# --- Assemble hybrid ISO ----------------------------------------------------
log "Building hybrid UEFI ISO -> $ISO_OUTPUT"
XORRISO_ARGS=(
  -as mkisofs
  -iso-level 3 -full-iso9660-filenames
  -volid "AURORA_${AURORA_VERSION//./_}"
  -appid  "${AURORA_NAME} ${AURORA_VERSION} live"
  -publisher "AuroraOS Project"
  -preparer  "AuroraOS build pipeline"
  # UEFI El Torito boot: points to the FAT image we built
  -eltorito-alt-boot
    -e boot/grub/efi.img -no-emul-boot
    -isohybrid-gpt-basdat
)
# Optional BIOS El Torito (legacy hosts only; Hyper-V Gen 2 uses UEFI)
if [ -f "$ISO_STAGE_DIR/boot/grub/eltorito.img" ]; then
  XORRISO_ARGS=(
    -as mkisofs
    -iso-level 3 -full-iso9660-filenames
    -volid "AURORA_${AURORA_VERSION//./_}"
    -appid  "${AURORA_NAME} ${AURORA_VERSION} live"
    -publisher "AuroraOS Project"
    -preparer  "AuroraOS build pipeline"
    -b boot/grub/eltorito.img -no-emul-boot
      -boot-load-size 4 -boot-info-table
    -eltorito-alt-boot
      -e boot/grub/efi.img -no-emul-boot
      -isohybrid-gpt-basdat
  )
fi

xorriso "${XORRISO_ARGS[@]}" -o "$ISO_OUTPUT" "$ISO_STAGE_DIR" 2>&1 | tail -10

ISO_SIZE=$(du -h "$ISO_OUTPUT" | cut -f1)
log "ISO ready: $ISO_OUTPUT  ($ISO_SIZE)"

# Checksums
sha256sum "$ISO_OUTPUT" > "${ISO_OUTPUT}.sha256"
log "SHA256: $(cat "${ISO_OUTPUT}.sha256")"
