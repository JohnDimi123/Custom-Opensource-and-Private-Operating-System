#!/bin/bash
# jarvis-build/30_configure.sh — enable services, splash, recovery, kiosk.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Configuring system behaviour"
[ "$(id -u)" -eq 0 ] || die "run as root"

mount -t proc proc "${CHROOT_DIR}/proc" 2>/dev/null || true
cleanup(){ umount -l "${CHROOT_DIR}/proc" 2>/dev/null || true; }
trap cleanup EXIT

cat > "${CHROOT_DIR}/configure_inner.sh" <<'INNER'
#!/bin/bash
set -euo pipefail

# Boot straight into the graphical (HUD) target, no display manager.
systemctl set-default graphical.target
systemctl enable jarvis-prep.service
systemctl enable jarvis-core.service
systemctl enable jarvis-voice.service
systemctl enable jarvis-ui.service
systemctl enable NetworkManager.service || true

# Don't run a getty on tty1 — the HUD owns it. Keep tty2 for recovery shell.
systemctl mask getty@tty1.service || true

# Plymouth splash theme
plymouth-set-default-theme jarvis || true
update-initramfs -u || true

# Auto-login operator on tty2 as an escape hatch.
mkdir -p /etc/systemd/system/getty@tty2.service.d
cat > /etc/systemd/system/getty@tty2.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin operator --noclear %I \$TERM
EOF

# Recovery: provide a clean root shell service used by jarvis-recovery.target.
cat > /etc/systemd/system/jarvis-recovery-shell.service <<EOF
[Unit]
Description=JARVIS Recovery Shell
[Service]
Type=idle
ExecStart=/bin/bash
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
[Install]
WantedBy=jarvis-recovery.target
EOF
ln -sf /etc/systemd/system/jarvis-recovery-shell.service \
   /etc/systemd/system/jarvis-recovery.target.wants/jarvis-recovery-shell.service 2>/dev/null || \
   { mkdir -p /etc/systemd/system/jarvis-recovery.target.wants; \
     ln -sf /etc/systemd/system/jarvis-recovery-shell.service \
        /etc/systemd/system/jarvis-recovery.target.wants/; }

# MOTD on the recovery tty.
cat > /etc/motd <<EOF

   J.A.R.V.I.S  OS  —  recovery console
   The HUD runs on tty1. This is tty2 (safe shell).
   Logs: /var/log/jarvis/   |   Reinstall to disk: sudo jarvis-pkg install-disk

EOF

# Clean apt caches to shrink the image.
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
INNER

chmod +x "${CHROOT_DIR}/configure_inner.sh"
chroot "${CHROOT_DIR}" /bin/bash /configure_inner.sh
rm -f "${CHROOT_DIR}/configure_inner.sh"

log "Configuration complete"
