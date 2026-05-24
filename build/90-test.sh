#!/bin/bash
# Stage 90: automated boot test in QEMU+OVMF (UEFI -- same path as Hyper-V Gen 2).
# Captures serial output, scans for kernel panics, and verifies a startup checkpoint.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ISO_OUTPUT" ] || die "ISO not found at $ISO_OUTPUT"
[ -x "$QEMU_BIN" ]   || die "QEMU binary not executable: $QEMU_BIN"
[ -f "$OVMF_CODE" ]  || die "OVMF firmware not found: $OVMF_CODE"

TEST_DIR="$WORK_DIR/test"
mkdir -p "$TEST_DIR"
cp "$OVMF_VARS_TEMPLATE" "$TEST_DIR/ovmf_vars.fd"
SERIAL_LOG="$TEST_DIR/serial.log"
: > "$SERIAL_LOG"

TIMEOUT_SEC="${AURORA_TEST_TIMEOUT:-180}"
log "Booting ISO under QEMU+OVMF for ${TIMEOUT_SEC}s. Serial -> $SERIAL_LOG"

# We boot headless: -display none -serial file:...  No graphics needed for boot test;
# Hyper-V will use the real display path via hyperv_drm. Network: user-mode slirp.
timeout --foreground "${TIMEOUT_SEC}s" \
  "$QEMU_BIN" \
    -machine q35,accel=tcg \
    -m 2048 -smp 2 -cpu max \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/ovmf_vars.fd" \
    -drive media=cdrom,readonly=on,file="$ISO_OUTPUT" \
    -boot d \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none \
    -serial file:"$SERIAL_LOG" \
    -no-reboot \
    -nodefaults \
  &
QEMU_PID=$!

# Watcher: stream serial as it arrives, kill on success markers
( tail -n +1 -f "$SERIAL_LOG" 2>/dev/null & TAIL_PID=$!
  while kill -0 $QEMU_PID 2>/dev/null; do
    if grep -qE 'Welcome to AuroraOS|aurora login:|reached target Graphical|Started LightDM' "$SERIAL_LOG" 2>/dev/null; then
      sleep 5
      kill $QEMU_PID 2>/dev/null || true
      break
    fi
    sleep 2
  done
  kill $TAIL_PID 2>/dev/null || true
) &

wait $QEMU_PID 2>/dev/null || true

log "QEMU exited. Analysing serial log ($(wc -l < "$SERIAL_LOG") lines)"

PASS=0; FAIL=0
check() {
  local desc="$1" pat="$2"
  if grep -qE "$pat" "$SERIAL_LOG" 2>/dev/null; then
    printf "  \033[1;32mPASS\033[0m  %s\n" "$desc"
    PASS=$((PASS+1))
  else
    printf "  \033[1;31mFAIL\033[0m  %s\n" "$desc"
    FAIL=$((FAIL+1))
  fi
}
check_no() {
  local desc="$1" pat="$2"
  if grep -qE "$pat" "$SERIAL_LOG" 2>/dev/null; then
    printf "  \033[1;31mFAIL\033[0m  %s   (matched: '%s')\n" "$desc" "$(grep -m1 -oE "$pat" "$SERIAL_LOG")"
    FAIL=$((FAIL+1))
  else
    printf "  \033[1;32mPASS\033[0m  %s\n" "$desc"
    PASS=$((PASS+1))
  fi
}

echo
echo "===== AuroraOS Boot Test Report ====="
check    "GRUB started"               'GRUB|Booting'
check    "Linux kernel started"       'Linux version|Command line:'
check    "live-boot mounted squashfs" 'live-boot|filesystem.squashfs|Live system'
check    "systemd reached userspace"  'systemd\[1\]|Welcome to'
check    "Graphical target reached"   'reached target Graphical|Started LightDM|aurora login:'
check_no "No kernel panic"            'Kernel panic|---\[ end Kernel panic'
check_no "No segfault in PID 1"       'systemd\[1\].*Segmentation fault'
check_no "No 'unable to mount root'"  'unable to mount root|VFS: Cannot open root'

echo "-------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
echo "Full log: $SERIAL_LOG"

if [ "$FAIL" -gt 0 ]; then
  log "Boot test had failures. Last 60 lines of serial:"
  tail -n 60 "$SERIAL_LOG"
  exit 1
fi
log "Boot test PASSED"
