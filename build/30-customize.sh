#!/bin/bash
# Stage 30: lay our overlay over the rootfs, then run hooks inside the chroot
# to wire up users, services, theme, plymouth, etc.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ROOTFS_DIR/.packages-installed" ] || die "Run 20-packages.sh first"

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

log "Generating dynamic assets (wallpaper, icons, plymouth theme)"
"$ROOT_DIR/build/assets/generate-assets.sh"

log "Copying overlay to rootfs"
rsync -a --chown=root:root "$ROOT_DIR/overlay/" "$ROOTFS_DIR/"

# Make every shell script we ship executable
find "$ROOTFS_DIR/usr/bin" -name 'aurora-*' -exec chmod 755 {} \;
find "$ROOTFS_DIR/usr/bin" -name 'aurora-*' -exec chown root:root {} \;

log "Installing custom apps from apps/ into rootfs"
for app in aurora-settings aurora-welcome aurora-about; do
  if [ -d "$ROOT_DIR/apps/$app" ]; then
    install -d "$ROOTFS_DIR/usr/lib/aurora/$app"
    cp -r "$ROOT_DIR/apps/$app/." "$ROOTFS_DIR/usr/lib/aurora/$app/"
    # Wrapper script in /usr/bin
    cat > "$ROOTFS_DIR/usr/bin/$app" <<EOF
#!/bin/sh
exec /usr/bin/python3 /usr/lib/aurora/$app/main.py "\$@"
EOF
    chmod 755 "$ROOTFS_DIR/usr/bin/$app"
  fi
done

mount_chroot

log "Configuring inside chroot"
cat > "$ROOTFS_DIR/tmp/customize-inside.sh" <<'CHROOT_EOF'
#!/bin/bash
set -e

# --- Identity -----------------------------------------------------------------
echo "aurora" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   aurora
::1         localhost ip6-localhost ip6-loopback
EOF

# --- Locale + timezone --------------------------------------------------------
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo "UTC" > /etc/timezone

# --- Live user with autologin -------------------------------------------------
useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev,users,cdrom aurora || true
echo "aurora:aurora" | chpasswd
echo "root:aurora"  | chpasswd
# passwordless sudo for the live session
echo "aurora ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/aurora-live
chmod 0440 /etc/sudoers.d/aurora-live

# Skel -> aurora user
if [ -d /etc/skel ]; then
  cp -rn /etc/skel/. /home/aurora/ 2>/dev/null || true
  chown -R aurora:aurora /home/aurora
fi

# --- LightDM autologin --------------------------------------------------------
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-aurora.conf <<EOF
[Seat:*]
autologin-user=aurora
autologin-user-timeout=0
user-session=openbox
greeter-session=lightdm-gtk-greeter
EOF
# LightDM-GTK greeter theming
mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
cat > /etc/lightdm/lightdm-gtk-greeter.conf.d/50-aurora.conf <<EOF
[greeter]
theme-name=Aurora
icon-theme-name=Aurora
font-name=Inter 11
background=/usr/share/backgrounds/aurora/aurora-default.png
EOF

# --- Default GTK theme + cursor + icons --------------------------------------
mkdir -p /etc/gtk-3.0
cat > /etc/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=Aurora
gtk-icon-theme-name=Aurora
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=true
gtk-enable-animations=true
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF

# --- Default user dirs --------------------------------------------------------
sudo -u aurora xdg-user-dirs-update --set DESKTOP /home/aurora/Desktop || true

# --- Services -----------------------------------------------------------------
systemctl enable lightdm.service NetworkManager.service systemd-timesyncd.service || true
systemctl set-default graphical.target

# Make sure live-config will run on boot
systemctl enable live-config.service 2>/dev/null || true

# --- Plymouth (boot splash) ---------------------------------------------------
if [ -d /usr/share/plymouth/themes/aurora ]; then
  plymouth-set-default-theme -R aurora || true
fi

# --- GRUB defaults inside the rootfs (used by installer) ----------------------
cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="AuroraOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=auto
EOF

# --- /etc/os-release ----------------------------------------------------------
cat > /etc/os-release <<EOF
NAME="AuroraOS"
PRETTY_NAME="AuroraOS 1.0 (Lumen)"
ID=aurora
ID_LIKE=debian
VERSION="1.0 (Lumen)"
VERSION_ID="1.0"
VERSION_CODENAME=lumen
HOME_URL="https://github.com/JohnDimi123/Custom-Opensource-and-Private-Operating-System"
SUPPORT_URL="https://github.com/JohnDimi123/Custom-Opensource-and-Private-Operating-System/issues"
EOF
ln -sf /etc/os-release /usr/lib/os-release

# Banner shown on TTY login
cat > /etc/issue <<EOF
AuroraOS 1.0 (Lumen) \\n \\l

EOF

# Permission fix
chown -R aurora:aurora /home/aurora || true

# Re-enable services we suppressed during package install
rm -f /usr/sbin/policy-rc.d
true
CHROOT_EOF

chmod +x "$ROOTFS_DIR/tmp/customize-inside.sh"
chroot "$ROOTFS_DIR" /tmp/customize-inside.sh
rm -f "$ROOTFS_DIR/tmp/customize-inside.sh"

touch "$ROOTFS_DIR/.customized"
log "Customization complete: $(du -sh "$ROOTFS_DIR" | cut -f1)"
