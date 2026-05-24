#!/bin/bash
# Verify the build host has everything we need. AL2023 specifically.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

log "Checking prerequisites"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
}

for c in xorriso mksquashfs grub2-mkstandalone mkfs.vfat mcopy mmd rsync wget gpg ar tar xz cpio; do
  need_cmd "$c"
done

# Provide debootstrap (not in AL2023 repos) by extracting upstream Debian package.
if ! command -v debootstrap >/dev/null 2>&1; then
  log "Installing debootstrap from upstream Debian package"
  TMPD=$(mktemp -d)
  cd "$TMPD"
  # Pick the latest deb12u* point release of debootstrap currently in pool
  DEB_NAME=$(curl -s "http://ftp.debian.org/debian/pool/main/d/debootstrap/" \
    | grep -oE 'debootstrap_1\.0\.[0-9]+(\+nmu[0-9]+)?(\+deb12u[0-9]+)?_all\.deb' \
    | sort -V | tail -1)
  if [ -z "$DEB_NAME" ]; then
    DEB_NAME="debootstrap_1.0.143_all.deb"
  fi
  wget -q "http://ftp.debian.org/debian/pool/main/d/debootstrap/$DEB_NAME" -O debootstrap.deb \
    || die "Could not download debootstrap ($DEB_NAME)"
  ar x debootstrap.deb
  mkdir -p extracted && tar -C extracted -xf data.tar.*
  cp -r extracted/usr/share/debootstrap /usr/share/
  install -m755 extracted/usr/sbin/debootstrap /usr/sbin/debootstrap
  cd /
  rm -rf "$TMPD"
fi
need_cmd debootstrap

# Install Python Pillow for asset generation (wallpapers, plymouth)
if ! python3 -c "import PIL" 2>/dev/null; then
  log "Installing Python Pillow for asset generation"
  pip install --quiet --break-system-packages Pillow 2>/dev/null \
    || pip3 install --quiet --break-system-packages Pillow 2>/dev/null \
    || warn "Pillow install failed; wallpaper/plymouth generation will be skipped"
fi

# Required for chroot
[ -d /proc ] || die "no /proc"
[ "$(id -u)" -eq 0 ] || die "must run as root"

log "All prerequisites satisfied. debootstrap=$(debootstrap --version | head -1)"
