#!/bin/bash
# build_jarvis_iso.sh — one command to build the bootable JARVIS OS ISO.
#
#   sudo ./build_jarvis_iso.sh                # core build (fast)
#   sudo JARVIS_FULL_VOICE=1 ./build_jarvis_iso.sh   # bake full voice stack
#
# Output: ./dist/jarvis-os.iso  (hybrid BIOS+UEFI, boots in any VM or real HW)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${HERE}/jarvis-build"
source "${BUILD}/config.sh"

banner() {
cat <<'EOF'
   ___  _____ ______      _____  _____
  |_  |/ _ \ | ___ \ \   / /_  |/  ___|
    | / /_\ \| |_/ /\ \ / /  | |\ `--.    O P E R A T I N G
    | |  _  ||    /  \ V /   | | `--. \      S Y S T E M
/\__/ / | | || |\ \   | |   _| |/\__/ /
\____/\_| |_/\_| \_|  \_/   \___/\____/   build pipeline

EOF
}

banner
[ "$(id -u)" -eq 0 ] || die "Please run as root:  sudo ./build_jarvis_iso.sh"

STAGES=(
  "00_deps.sh:Install host build tools"
  "10_bootstrap.sh:Bootstrap minimal Debian"
  "20_provision.sh:Install kernel, X, runtimes & Jarvis"
  "30_configure.sh:Configure services, splash, recovery"
  "40_squashfs.sh:Compress root filesystem"
  "50_bootloader.sh:Configure BIOS + UEFI bootloaders"
  "60_iso.sh:Generate jarvis-os.iso"
)

START=$(date +%s)
for entry in "${STAGES[@]}"; do
    script="${entry%%:*}"; desc="${entry#*:}"
    echo
    log "──────────────────────────────────────────────"
    log "STAGE ${script%%_*}  —  ${desc}"
    log "──────────────────────────────────────────────"
    bash "${BUILD}/${script}"
done

END=$(date +%s)
echo
log "✓ BUILD COMPLETE in $(( (END-START)/60 ))m $(( (END-START)%60 ))s"
log "  ISO → ${OUTPUT_DIR}/${JARVIS_ISO_NAME}"
log "  Attach it to a VM and boot — Jarvis comes up automatically."
log "  Default login (recovery tty2): operator / jarvis"
log "  To enable Claude, set JARVIS_ANTHROPIC_KEY in /etc/jarvis/jarvis.env"
