#!/bin/bash
# Generate original visual assets for AuroraOS.
# Everything here is procedurally produced -> no third-party copyright.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../00-config.sh"

OVERLAY="$ROOT_DIR/overlay"

log "Generating wallpapers (PNG via Python+PIL or pure SVG fallback)"
python3 "$SCRIPT_DIR/gen-wallpaper.py" \
  --out "$OVERLAY/usr/share/backgrounds/aurora" \
  || warn "Wallpaper generation failed; using SVG fallback"

log "Generating Aurora GTK theme"
mkdir -p "$OVERLAY/usr/share/themes/Aurora"
cp -r "$SCRIPT_DIR/theme/Aurora/." "$OVERLAY/usr/share/themes/Aurora/"

log "Generating Aurora icon theme (minimal -- inherits Adwaita)"
mkdir -p "$OVERLAY/usr/share/icons/Aurora"
cp -r "$SCRIPT_DIR/icons/Aurora/." "$OVERLAY/usr/share/icons/Aurora/"

log "Generating Plymouth theme"
mkdir -p "$OVERLAY/usr/share/plymouth/themes/aurora"
cp -r "$SCRIPT_DIR/plymouth/aurora/." "$OVERLAY/usr/share/plymouth/themes/aurora/"
python3 "$SCRIPT_DIR/gen-plymouth-images.py" "$OVERLAY/usr/share/plymouth/themes/aurora"

log "Asset generation done"
