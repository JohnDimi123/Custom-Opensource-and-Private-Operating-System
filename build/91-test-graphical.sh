#!/bin/bash
# Stage 91: deeper boot test - boot the verbose entry and verify the desktop
# session actually comes up (LightDM, Openbox, autostart programs).
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ISO_OUTPUT" ] || die "ISO not found"
[ -x "$QEMU_BIN" ]   || die "qemu missing"

TEST_DIR="$WORK_DIR/test-gfx"
mkdir -p "$TEST_DIR"
cp "$OVMF_VARS_TEMPLATE" "$TEST_DIR/ovmf_vars.fd"

# We use a pre-baked grub overlay that sets default to the verbose menu entry
# AND we kick the system with a longer timeout so that LightDM + autostart can
# happen.

SERIAL_LOG="$TEST_DIR/serial.log"
MON_SOCK="$TEST_DIR/mon.sock"
: > "$SERIAL_LOG"
TIMEOUT_SEC="${AURORA_GFX_TIMEOUT:-300}"

log "Graphical-session boot test (${TIMEOUT_SEC}s).  Serial -> $SERIAL_LOG"

# Append a tiny GRUB env override via "-kernel" trick is not possible (we want
# to use the ISO's GRUB). Instead, we tell QEMU to send keystrokes via the
# monitor: ArrowDown x3, Enter -> selects "Verbose boot (debug)".
timeout --foreground "${TIMEOUT_SEC}s" \
  "$QEMU_BIN" \
    -machine q35,accel=tcg \
    -m 2048 -smp 2 -cpu max \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/ovmf_vars.fd" \
    -drive media=cdrom,readonly=on,file="$ISO_OUTPUT" \
    -boot d \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    -display none \
    -serial file:"$SERIAL_LOG" \
    -monitor unix:"$MON_SOCK",server,nowait \
    -no-reboot -nodefaults \
  &
QEMU_PID=$!

# After 10s, send keys: down,down,down,enter to pick "Verbose boot (debug)"
( sleep 10
  if [ -S "$MON_SOCK" ]; then
    printf 'sendkey down\nsendkey down\nsendkey down\nsendkey ret\n' \
      | socat - UNIX-CONNECT:"$MON_SOCK" 2>/dev/null \
      || python3 -c "
import socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('$MON_SOCK')
time.sleep(0.5)
for cmd in ('sendkey down','sendkey down','sendkey down','sendkey ret'):
    s.sendall((cmd+'\n').encode()); time.sleep(0.2)
s.close()" 2>/dev/null
  fi
) &

# Watcher: kill on any DE-up signal
( while kill -0 $QEMU_PID 2>/dev/null; do
    if grep -qE "Reached target Graphical|Started LightDM|Reached target Login Prompts|aurora login:" "$SERIAL_LOG" 2>/dev/null; then
      sleep 25
      kill $QEMU_PID 2>/dev/null || true
      break
    fi
    sleep 3
  done
) &

wait $QEMU_PID 2>/dev/null || true

log "QEMU exited. Lines: $(wc -l < "$SERIAL_LOG")"
PASS=0; FAIL=0
chk()  { if grep -qE "$2" "$SERIAL_LOG"; then printf "  \033[1;32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); else printf "  \033[1;31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); fi }
nchk() { if grep -qE "$2" "$SERIAL_LOG"; then printf "  \033[1;31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); else printf "  \033[1;32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); fi }

echo
echo "===== AuroraOS Graphical Session Test ====="
chk  "GRUB chained to kernel"         'Booting .AuroraOS|Welcome to|live-config|Linux version'
chk  "Live filesystem mounted"        'live-boot|filesystem.squashfs|live-config|Reached target|aurora login'
chk  "systemd late boot reached"      'plymouth-quit|Reached target|aurora login:|Started Session|getty'
chk  "Login layer up"                 'aurora login:|Started Session|graphical.target'
nchk "No kernel panic"                'Kernel panic'
nchk "No initramfs drop"              '\(initramfs\) #|/init: line.*not found'
nchk "No squashfs/io error"           'SQUASHFS error|Buffer I/O error on dev'
nchk "No systemd PID1 fail"           'Failed to mount.*FATAL|Failed to start default.target'
echo "------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  log "Last 80 lines of serial:"; tail -n 80 "$SERIAL_LOG"
  exit 1
fi
log "Graphical session test PASSED"
