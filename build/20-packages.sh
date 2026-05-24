#!/bin/bash
# Stage 20: install the kernel, X11, desktop environment, and apps inside the chroot.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ROOTFS_DIR/.bootstrapped" ] || die "Run 10-bootstrap.sh first"

# Bind mount kernel filesystems so apt's maintainer scripts work
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

log "Configuring apt sources"
cat > "$ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb $DEBIAN_MIRROR $DEBIAN_RELEASE $DEBIAN_COMPONENTS
deb $DEBIAN_MIRROR ${DEBIAN_RELEASE}-updates $DEBIAN_COMPONENTS
deb $DEBIAN_MIRROR ${DEBIAN_RELEASE}-backports $DEBIAN_COMPONENTS
deb http://security.debian.org/debian-security ${DEBIAN_RELEASE}-security $DEBIAN_COMPONENTS
EOF

# Stop services from auto-starting during install
cat > "$ROOTFS_DIR/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$ROOTFS_DIR/usr/sbin/policy-rc.d"

mount_chroot

# These flags speed apt up significantly inside the chroot
APTOPTS="-y --no-install-recommends -o Dpkg::Options::=--force-confnew -o Acquire::Retries=3"

log "Updating apt cache"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tail -5

# --- Package list ------------------------------------------------------------
# Categorised so the architecture is readable.

CORE=(
  # init + system
  systemd systemd-sysv dbus polkitd udev
  # network
  network-manager iproute2 isc-dhcp-client iputils-ping ca-certificates wget curl
  # firmware (Hyper-V uses none for storage/network/console; firmware-linux for safety)
  firmware-linux firmware-linux-nonfree firmware-misc-nonfree
  # locale + timezone
  locales tzdata console-setup keyboard-configuration
  # essentials
  sudo passwd less nano vim-tiny bash-completion psmisc procps
  # filesystems
  e2fsprogs dosfstools ntfs-3g exfatprogs btrfs-progs
)

KERNEL=(
  linux-image-amd64 linux-headers-amd64
  initramfs-tools
)

LIVE=(
  # live-boot brings the squashfs+overlay live system; live-config does first-boot setup
  live-boot live-config live-config-systemd
)

BOOTLOADER=(
  # Needed inside the rootfs for Calamares to install GRUB during installation
  grub-efi-amd64 grub-efi-amd64-bin grub-common grub2-common
  efibootmgr efivar
  # Optional BIOS fallback (Hyper-V Gen 2 doesn't need it but is harmless)
  grub-pc-bin
)

XORG=(
  xserver-xorg xserver-xorg-core xserver-xorg-input-libinput
  # Hyper-V exposes hyperv_drm/hyperv_fb framebuffer; modesetting + fbdev cover it.
  xserver-xorg-video-fbdev xserver-xorg-video-vesa
  xinit x11-xserver-utils x11-utils xterm
)

DESKTOP=(
  # Window manager + compositor + panel + start menu + notifications + launcher
  openbox obconf
  picom               # compositor: rounded corners, transparency, blur, fade animations
  tint2               # taskbar (configured for centered Win11-style)
  jgmenu              # start menu
  rofi                # search/launcher (Win+S spotlight equivalent)
  dunst               # notification daemon
  feh                 # wallpaper setter
  conky-std           # optional: small system info widget
  # File manager + terminal
  pcmanfm xfce4-terminal
  # Display manager with autologin
  lightdm lightdm-gtk-greeter
  # Sound
  pipewire pipewire-pulse wireplumber pavucontrol alsa-utils
  # Useful utilities exposed in the menu
  galculator mousepad arandr lxappearance xarchiver file-roller
  gnome-screenshot
  # Power/brightness (works in VMs too)
  brightnessctl
  # GTK runtime for our custom apps
  python3 python3-gi gir1.2-gtk-3.0 gir1.2-glib-2.0 gir1.2-pango-1.0
  python3-psutil python3-yaml
  # Theming infrastructure (we ship our own theme on top)
  gtk2-engines-murrine gtk2-engines-pixbuf
  # Fonts (Inter + DejaVu fallback)
  fonts-inter fonts-dejavu fonts-dejavu-core fonts-noto-color-emoji
  # Boot splash
  plymouth plymouth-themes plymouth-label
  # XDG basics
  xdg-utils xdg-user-dirs
  # Image viewer
  qimgv
)

INSTALLER=(
  # Calamares: graphical OS installer (offline, doesn't need network)
  calamares calamares-settings-debian
  # Partitioning backend
  parted kpartx dosfstools
  # squashfs unpacking on install
  squashfs-tools rsync
)

log "Installing CORE packages"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${CORE[@]}" 2>&1 | tail -3

log "Installing KERNEL"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${KERNEL[@]}" 2>&1 | tail -3

log "Installing LIVE infrastructure"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${LIVE[@]}" 2>&1 | tail -3

log "Installing BOOTLOADER tools"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${BOOTLOADER[@]}" 2>&1 | tail -3

log "Installing XORG"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${XORG[@]}" 2>&1 | tail -3

log "Installing DESKTOP environment + apps"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${DESKTOP[@]}" 2>&1 | tail -3

log "Installing INSTALLER (Calamares)"
chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install $APTOPTS "${INSTALLER[@]}" 2>&1 | tail -3 || warn "Calamares install had warnings (continuing)"

log "Package install size: $(du -sh "$ROOTFS_DIR" | cut -f1)"
touch "$ROOTFS_DIR/.packages-installed"
