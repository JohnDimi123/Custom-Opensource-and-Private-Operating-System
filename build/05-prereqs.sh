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
  wget -q "http://ftp.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.128+nmu2+deb12u3_all.deb" -O debootstrap.deb \
    || wget -q "http://ftp.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.128+nmu2+deb12u4_all.deb" -O debootstrap.deb \
    || die "Could not download debootstrap"
  ar x debootstrap.deb
  mkdir -p extracted && tar -C extracted -xf data.tar.*
  cp -r extracted/usr/share/debootstrap /usr/share/
  install -m755 extracted/usr/sbin/debootstrap /usr/sbin/debootstrap
  install -m755 extracted/usr/share/debootstrap/debootstrap /usr/share/debootstrap/debootstrap
  cd /
  rm -rf "$TMPD"
fi
need_cmd debootstrap

# Required for chroot
[ -d /proc ] || die "no /proc"
[ "$(id -u)" -eq 0 ] || die "must run as root"

log "All prerequisites satisfied. debootstrap=$(debootstrap --version | head -1)"
