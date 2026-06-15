# JARVIS OS

A bootable Linux distribution that launches **directly into a fullscreen AI assistant**.
No desktop environment — the assistant *is* the operating system. Built on Debian 12
(bookworm) minimal, it boots in VirtualBox, VMware, Hyper-V, Proxmox, and on real hardware.

```
Firmware → ISOLINUX/GRUB → kernel + live-boot → systemd
   → jarvis-core (orchestrator) + jarvis-voice + jarvis-ui (Iron-Man HUD kiosk)
```

## Build the ISO

```bash
sudo ./build_jarvis_iso.sh
# → dist/jarvis-os.iso   (hybrid BIOS + UEFI bootable)
```

Bake the full local voice stack (whisper + openWakeWord + Piper) into the image:

```bash
sudo JARVIS_FULL_VOICE=1 ./build_jarvis_iso.sh
```

Requirements on the build host: Debian/Ubuntu with root, ~10 GB free, internet access.
The build runs seven stages (`jarvis-build/00…60`), each independently runnable.

## Boot & use

1. Attach `dist/jarvis-os.iso` to a VM (≥2 vCPU, 4 GB RAM, EFI or BIOS firmware) and boot.
2. The arc-reactor splash appears, then the HUD comes up fullscreen on tty1.
3. Say **"Jarvis"** to wake it, or type into the command bar at the bottom.
4. tty2 is a recovery shell (`operator` / `jarvis`).

### Enable Claude
Without a key, Jarvis runs offline (local model if present, else a rule-based responder).
To use Anthropic Claude, set a key in `/etc/jarvis/jarvis.env`:

```bash
echo 'JARVIS_ANTHROPIC_KEY=sk-ant-...' | sudo tee -a /etc/jarvis/jarvis.env
sudo systemctl restart jarvis-core
```

## Architecture

| Module | Purpose |
|--------|---------|
| `jarvis-core/`      | Orchestrator daemon, intent routing, sandbox, sysmon, vision |
| `jarvis-ai/`        | Claude client + local llama.cpp fallback + offline responder |
| `jarvis-memory/`    | SQLite long-term memory, user profiles, plugins |
| `jarvis-voice/`     | Wake word, STT (whisper), TTS (Piper/espeak), barge-in |
| `jarvis-ui/`        | Electron Iron-Man HUD (arc reactor, telemetry, notifications, plugins) |
| `jarvis-services/`  | systemd units, Xorg kiosk, Plymouth splash, recovery target |
| `jarvis-installer/` | `jarvis-pkg` package/plugin/model installer + install-to-disk |
| `jarvis-build/`     | debootstrap → provision → squashfs → bootloader → ISO pipeline |

See `ARCHITECTURE.md` for the full design, data flow, and IPC contract.

## Security
- **Sandboxed commands** — allow-list + deny-list + firejail + timeouts (`jarvis-core/sandbox.py`).
- **Permission system** — capability-gated file/shell/hardware/net access; default-deny.
- **Logging** — structured JSON logs in `/var/log/jarvis/`.
- **Recovery mode** — dedicated boot entry → root shell, no UI.

## Install to disk
From a running live session:

```bash
sudo jarvis-pkg install-disk
```

## Notes on responsible use
The voice/vision features capture microphone, screen, and webcam data locally. Anyone
deploying this should make sure users are aware of and consent to that capture, and should
keep the Anthropic API key out of shared images.
