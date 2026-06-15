# JARVIS OS — Architecture

## 1. Concept
JARVIS OS is a Debian-minimal–based live Linux distribution that boots **directly into a
fullscreen AI assistant** instead of a desktop environment. There is no GNOME/KDE/XFCE.
A single Xorg session launches the Jarvis UI in kiosk mode. The assistant *is* the OS shell.

## 2. Boot chain
```
Firmware (BIOS/UEFI)
  └─ ISOLINUX (BIOS) / GRUB (UEFI)        ← jarvis-build/bootloader
       └─ Linux kernel + initrd (live-boot)
            └─ systemd
                 ├─ jarvis-splash.service   (Plymouth boot splash)
                 ├─ jarvis-core.service      (orchestrator daemon, /jarvis-core)
                 ├─ jarvis-voice.service     (wake word + STT + TTS, /jarvis-voice)
                 └─ jarvis-ui.service        (Xorg kiosk → Electron HUD, /jarvis-ui)
```
No display-manager, no login shell on tty1 — the UI service owns the screen.
A hidden recovery target (`jarvis-recovery.target`) drops to a root shell on tty2.

## 3. Component map
| Path                | Role |
|---------------------|------|
| `/jarvis-core`      | Python orchestrator daemon. Routes intents between voice, AI, memory, system-control. Exposes a local WebSocket (`ws://127.0.0.1:8765`) the UI subscribes to. |
| `/jarvis-ai`        | AI backends. `claude_client.py` (Anthropic API) + `local_model.py` (llama.cpp fallback). Unified `AIRouter`. |
| `/jarvis-memory`    | SQLite long-term memory, per-user profiles, vector recall, conversation log. |
| `/jarvis-voice`     | Wake-word (openWakeWord "jarvis"), STT (faster-whisper), TTS (Piper), barge-in/interrupt. |
| `/jarvis-ui`        | Electron HUD (Iron-Man HUD: arc reactor, mic state, system stats, thinking state, notifications, plugin manager). |
| `/jarvis-services`  | systemd unit files, Xorg kiosk config, Plymouth theme, udev rules. |
| `/jarvis-installer` | Package installer + "install to disk" tool + plugin installer. |
| `/jarvis-build`     | debootstrap chroot builder, bootloader config, squashfs + ISO generator. |

## 4. Data flow (one interaction)
```
mic → voice.wakeword("jarvis") → voice.stt → text
   → core.intent_router → {ai | system_control}
        ai → memory.recall + AIRouter.ask(claude→local) → reply
        system_control → sandbox.exec(whitelisted) → result
   → core → voice.tts(reply)  +  ui.push(reply, state)
   → memory.store(turn)
```

## 5. Inter-process contract
All daemons talk over a local **JSON line protocol**:
- Core ⇄ UI: WebSocket `127.0.0.1:8765`.
- Core ⇄ Voice: Unix socket `/run/jarvis/voice.sock`.
- Message envelope: `{"type": "...", "ts": <epoch>, "payload": {...}}`
  Types: `wake`, `listening`, `transcript`, `thinking`, `speaking`, `reply`,
          `stat`, `notify`, `interrupt`, `intent`, `plugin`.

## 6. Security model
- **Sandboxed commands**: every shell/system action passes through
  `jarvis-core/sandbox.py`, which enforces a command whitelist + regex deny-list,
  runs under `firejail` when available, and times out.
- **Permission system**: capabilities (`files.read`, `files.write`, `shell.exec`,
  `hardware.power`, `net.access`) declared per-plugin and per-intent; denied by default.
- **Logging**: structured JSON logs to `/var/log/jarvis/*.log` (rotated).
- **Recovery mode**: GRUB/ISOLINUX entry → `jarvis-recovery.target` → root shell, no UI.

## 7. AI fallback ladder
1. Anthropic Claude (`claude-opus-4-8` default) if `JARVIS_ANTHROPIC_KEY` set and online.
2. Local llama.cpp GGUF model (if present in `/opt/jarvis/models`).
3. Deterministic rule-based responder (always available, offline).

## 8. Build pipeline (Phase 6)
```
build_jarvis_iso.sh
 ├─ 00 deps        install host build tools
 ├─ 10 bootstrap   debootstrap minimal Debian → chroot
 ├─ 20 provision   install kernel, Xorg, python, node, jarvis code, services
 ├─ 30 configure   enable services, splash, kiosk, recovery, default user
 ├─ 40 squashfs    mksquashfs the chroot → filesystem.squashfs
 ├─ 50 bootloader  ISOLINUX (BIOS) + GRUB (UEFI) + EFI image
 └─ 60 iso         xorriso → jarvis-os.iso  (hybrid BIOS+UEFI bootable)
```
Output: `jarvis-os.iso` (boots in VirtualBox, VMware, Hyper-V, Proxmox, real HW).
