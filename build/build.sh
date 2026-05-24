#!/bin/bash
# Top-level build orchestrator. Runs every stage in order.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/00-config.sh"

# Run stages
"$SCRIPT_DIR/05-prereqs.sh"
"$SCRIPT_DIR/10-bootstrap.sh"
"$SCRIPT_DIR/20-packages.sh"
"$SCRIPT_DIR/30-customize.sh"
"$SCRIPT_DIR/40-clean.sh"
"$SCRIPT_DIR/50-squashfs.sh"
"$SCRIPT_DIR/60-iso.sh"

if [ "${SKIP_TEST:-0}" != "1" ]; then
  "$SCRIPT_DIR/90-test.sh" || warn "Boot test reported failures (continuing; see report)"
fi

log "BUILD COMPLETE"
log "ISO:      $ISO_OUTPUT"
log "SHA256:   $(cat "${ISO_OUTPUT}.sha256" 2>/dev/null || echo missing)"
log "Size:     $(du -h "$ISO_OUTPUT" | cut -f1)"
