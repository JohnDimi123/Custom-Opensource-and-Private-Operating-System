#!/bin/bash
# jarvis-build/10_bootstrap.sh — create a minimal Debian chroot.
set -euo pipefail
source "$(dirname "$0")/config.sh"

log "Bootstrapping minimal ${JARVIS_DISTRO} (${JARVIS_SUITE})"
[ "$(id -u)" -eq 0 ] || die "run as root"

rm -rf "${CHROOT_DIR}"
mkdir -p "${CHROOT_DIR}"

debootstrap --arch="${JARVIS_ARCH}" --variant=minbase \
    --include=systemd,systemd-sysv,dbus,locales,sudo,ca-certificates \
    "${JARVIS_SUITE}" "${CHROOT_DIR}" "${JARVIS_MIRROR}"

# Basic apt sources inside the chroot.
cat > "${CHROOT_DIR}/etc/apt/sources.list" <<EOF
deb ${JARVIS_MIRROR} ${JARVIS_SUITE} main contrib non-free non-free-firmware
deb ${JARVIS_MIRROR} ${JARVIS_SUITE}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${JARVIS_SUITE}-security main contrib non-free non-free-firmware
EOF

echo "${JARVIS_HOSTNAME}" > "${CHROOT_DIR}/etc/hostname"
cat > "${CHROOT_DIR}/etc/hosts" <<EOF
127.0.0.1   localhost ${JARVIS_HOSTNAME}
::1         localhost ip6-localhost ip6-loopback
EOF

log "Bootstrap complete → ${CHROOT_DIR}"
