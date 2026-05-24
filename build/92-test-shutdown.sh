#!/bin/bash
# Stage 92: shutdown test - reach login, send a 'poweroff' keystroke sequence
# via the QEMU monitor to a logged-in console, verify clean shutdown.
set -euo pipefail
. "$(dirname "$0")/00-config.sh"

[ -f "$ISO_OUTPUT" ] || die "ISO not found"
TEST_DIR="$WORK_DIR/test-shutdown"
mkdir -p "$TEST_DIR"
cp "$OVMF_VARS_TEMPLATE" "$TEST_DIR/ovmf_vars.fd"
SERIAL_LOG="$TEST_DIR/serial.log"
MON_SOCK="$TEST_DIR/mon.sock"
: > "$SERIAL_LOG"
TIMEOUT_SEC="${AURORA_SHUTDOWN_TIMEOUT:-300}"

log "Shutdown test (${TIMEOUT_SEC}s)"

timeout --foreground "${TIMEOUT_SEC}s" \
  "$QEMU_BIN" \
    -machine q35,accel=tcg \
    -m 1024 -smp 2 -cpu max \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/ovmf_vars.fd" \
    -drive media=cdrom,readonly=on,file="$ISO_OUTPUT" \
    -boot d \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    -display none \
    -serial unix:"$TEST_DIR/serial.sock",server,nowait \
    -monitor unix:"$MON_SOCK",server,nowait \
    -no-reboot -nodefaults \
  &
QEMU_PID=$!

# Connect to the serial socket, log it, and once we see 'aurora login:' send
# username, password, then 'sudo poweroff'.
( sleep 3
  python3 <<EOF
import socket, time, sys, os, re
sp = '$TEST_DIR/serial.sock'
lp = '$SERIAL_LOG'
for _ in range(40):
    if os.path.exists(sp): break
    time.sleep(0.5)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(sp)
s.setblocking(False)
buf = b''
state = 'wait_login'
deadline = time.time() + 240
log = open(lp, 'ab')
while time.time() < deadline:
    try:
        chunk = s.recv(4096)
        if chunk: buf += chunk; log.write(chunk); log.flush()
    except BlockingIOError: pass
    if state == 'wait_login' and re.search(rb'aurora login:', buf):
        s.sendall(b'aurora\n'); state = 'wait_pw'; buf = b''
        time.sleep(1)
    elif state == 'wait_pw' and re.search(rb'[Pp]assword:', buf):
        s.sendall(b'aurora\n'); state = 'wait_prompt'; buf = b''
        time.sleep(2)
    elif state == 'wait_prompt' and re.search(rb'aurora@aurora:', buf):
        s.sendall(b'sudo poweroff\n'); state = 'shutting_down'; buf = b''
    elif state == 'shutting_down' and re.search(rb'Power(ing|ed) [Oo]ff|reboot: Power down|System Halted', buf):
        break
    time.sleep(0.2)
log.close()
EOF
) &
HELPER_PID=$!

wait $QEMU_PID 2>/dev/null || true
kill $HELPER_PID 2>/dev/null || true

echo
echo "===== AuroraOS Shutdown Test ====="
PASS=0; FAIL=0
chk(){ if grep -qE "$2" "$SERIAL_LOG"; then printf "  \033[1;32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); else printf "  \033[1;31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); fi; }
chk "Reached login prompt"  'aurora login:'
chk "Logged in as aurora"   'aurora@aurora|Linux aurora|Last login'
chk "Initiated poweroff"    'Reached target Power-Off|systemd-shutdown|reboot: Power down|System Halted|Powering off'
echo "----------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && log "Shutdown test PASSED" || { log "Shutdown test had failures"; tail -n 60 "$SERIAL_LOG"; exit 1; }
