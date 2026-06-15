#!/bin/bash
# jarvis-build/20_provision.sh — install kernel, X, runtimes, and Jarvis code.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Provisioning chroot"
[ "$(id -u)" -eq 0 ] || die "run as root"

# --- bind mounts for chroot operations ---
mount --bind /dev    "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
mount -t proc proc   "${CHROOT_DIR}/proc"
mount -t sysfs sys   "${CHROOT_DIR}/sys"
cleanup() {
    umount -l "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
    umount -l "${CHROOT_DIR}/dev"     2>/dev/null || true
    umount -l "${CHROOT_DIR}/proc"    2>/dev/null || true
    umount -l "${CHROOT_DIR}/sys"     2>/dev/null || true
}
trap cleanup EXIT

# --- copy Jarvis source tree into the image ---
log "Copying Jarvis source into /opt/jarvis"
install -d "${CHROOT_DIR}/opt/jarvis"
# python packages (import names use underscores)
cp -r "${JARVIS_ROOT}/jarvis-core"   "${CHROOT_DIR}/opt/jarvis/jarvis_core"
cp -r "${JARVIS_ROOT}/jarvis-ai"     "${CHROOT_DIR}/opt/jarvis/jarvis_ai"
cp -r "${JARVIS_ROOT}/jarvis-memory" "${CHROOT_DIR}/opt/jarvis/jarvis_memory"
cp -r "${JARVIS_ROOT}/jarvis-voice"  "${CHROOT_DIR}/opt/jarvis/jarvis_voice"
cp -r "${JARVIS_ROOT}/jarvis-ui"     "${CHROOT_DIR}/opt/jarvis/ui"
cp -r "${JARVIS_ROOT}/jarvis-installer" "${CHROOT_DIR}/opt/jarvis/installer"
cp "${JARVIS_ROOT}/jarvis-build/requirements.txt" "${CHROOT_DIR}/opt/jarvis/"

# --- service + config files ---
install -d "${CHROOT_DIR}/etc/jarvis"
cp "${JARVIS_ROOT}/jarvis-services/xinitrc" "${CHROOT_DIR}/etc/jarvis/xinitrc"
cp "${JARVIS_ROOT}/jarvis-services/"*.service "${CHROOT_DIR}/etc/systemd/system/"
cp "${JARVIS_ROOT}/jarvis-services/"*.target  "${CHROOT_DIR}/etc/systemd/system/"
install -d "${CHROOT_DIR}/usr/share/plymouth/themes/jarvis"
cp "${JARVIS_ROOT}/jarvis-services/plymouth/"* \
   "${CHROOT_DIR}/usr/share/plymouth/themes/jarvis/" 2>/dev/null || true

# default live env file
cat > "${CHROOT_DIR}/etc/jarvis/jarvis.env" <<EOF
# Set your Anthropic key to enable Claude. Without it Jarvis runs offline.
# JARVIS_ANTHROPIC_KEY=sk-ant-...
JARVIS_CLAUDE_MODEL=claude-opus-4-8
JARVIS_USER=${JARVIS_USER}
EOF

# --- inner provisioning script ---
cat > "${CHROOT_DIR}/provision_inner.sh" <<'INNER'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Kernel + live boot + firmware
apt-get install -y --no-install-recommends \
    linux-image-amd64 live-boot systemd-sysv \
    firmware-linux-free firmware-misc-nonfree \
    network-manager iproute2 iputils-ping \
    plymouth plymouth-themes

# Minimal X stack (NO desktop environment)
apt-get install -y --no-install-recommends \
    xserver-xorg-core xserver-xorg-video-all xserver-xorg-input-all \
    xinit x11-xserver-utils xdg-utils unclutter xterm

# Runtimes
apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    nodejs npm \
    firejail \
    alsa-utils espeak-ng \
    scrot tesseract-ocr fswebcam \
    pulseaudio

# Python deps (core only unless full voice requested)
pip3 install --break-system-packages --no-cache-dir \
    websockets psutil anthropic || true

if [ "${JARVIS_FULL_VOICE:-0}" = "1" ]; then
    pip3 install --break-system-packages --no-cache-dir \
        faster-whisper openwakeword piper-tts numpy pyaudio || true
    apt-get install -y --no-install-recommends portaudio19-dev || true
fi

# Electron for the HUD
cd /opt/jarvis/ui
npm install --no-audit --no-fund --omit=dev || npm install electron@31 --no-audit

# Create the operator user (kiosk + sudo for live tinkering)
useradd -m -s /bin/bash operator || true
echo "operator:jarvis" | chpasswd
echo "root:jarvis" | chpasswd
usermod -aG sudo,audio,video,plugdev operator
echo "operator ALL=(ALL) NOPASSWD: /opt/jarvis/installer/disk_install.sh" \
    > /etc/sudoers.d/jarvis

# jarvis-pkg on PATH
ln -sf /opt/jarvis/installer/jarvis-pkg.py /usr/local/bin/jarvis-pkg
chmod +x /usr/local/bin/jarvis-pkg /opt/jarvis/installer/*.sh

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
INNER

chmod +x "${CHROOT_DIR}/provision_inner.sh"
JARVIS_FULL_VOICE="${JARVIS_FULL_VOICE}" \
    chroot "${CHROOT_DIR}" /bin/bash -c "JARVIS_FULL_VOICE=${JARVIS_FULL_VOICE} /provision_inner.sh"
rm -f "${CHROOT_DIR}/provision_inner.sh"

log "Provisioning complete"
